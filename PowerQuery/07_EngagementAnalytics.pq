// ============================================================
// 07_EngagementAnalytics.pq
// Microsoft Graph API – Page Engagement (Reactions) and Sharing Activity
//
// Sources:
//   Graph API: GET /v1.0/sites/{id}/lists/Site%20Pages/items?$expand=fields
//   Graph API: GET /v1.0/reports/getSharePointActivityUserDetail(period)
//
// Auth:    Sites.Read.All, Reports.Read.All (client credentials via GraphAPIHelper)
// Notes:
//   - LikeCount / CommentCount are populated only when Reactions is enabled
//     in SharePoint Admin Center → Settings → "Allow commenting on modern pages"
//   - Share counts are aggregated from activity reports (not per-page)
// ============================================================

let
    // ── Unpack parameters ─────────────────────────────────────────────────────
    HubSiteUrl   = Parameters[HubSiteUrl],
    SpokeUrls    = Parameters[SpokeUrls],
    ReportPeriod = Parameters[ReportPeriod],
    GraphBaseUrl = Parameters[GraphBaseUrl],
    AuthHdr      = GraphAPIHelper[AuthHeader](),

    allSiteUrls = List.Combine({{HubSiteUrl}, SpokeUrls}),

    // ── Helper: resolve site URL → Graph site ID ──────────────────────────────
    ResolveSiteId = (siteUrl as text) as record =>
    let
        uri        = Uri.Parts(siteUrl),
        hostname   = uri[Host],
        scheme     = uri[Scheme],
        hostPrefix = scheme & "://" & hostname,
        afterHost  = Text.TrimStart(
                         if Text.StartsWith(siteUrl, hostPrefix)
                         then Text.Range(siteUrl, Text.Length(hostPrefix))
                         else uri[Path],
                         "/"),
        relPath    = Text.TrimStart(
                         if Text.StartsWith(Text.Lower(afterHost), "https://") or
                            Text.StartsWith(Text.Lower(afterHost), "http://")
                         then Uri.Parts(afterHost)[Path]
                         else afterHost,
                         "/"),
        raw        = Web.Contents(
                         GraphBaseUrl & "/sites/" & hostname & ":/" & relPath,
                         [Headers              = Record.Combine({[#"Content-Type" = "application/json"], AuthHdr}),
                          ManualStatusHandling = {400, 401, 403, 404, 500}]
                     ),
        parsed     = Json.Document(raw)
    in
        [SiteUrl = scheme & "://" & hostname & "/" & relPath,
         SiteId  = Record.FieldOrDefault(parsed, "id", "")],

    siteIdMap = List.Transform(allSiteUrls, (url) =>
                    try ResolveSiteId(url)
                    otherwise [SiteUrl = url, SiteId = ""]),

    // ── Helper: fetch pages with engagement fields for one site ──────────────
    // GET /v1.0/sites/{id}/lists/Site%20Pages/items?$expand=fields
    // No $select on fields – avoids 400 errors when LikeCount/CommentCount
    // columns don't exist (Reactions feature not enabled on the site).
    FetchPageEngagement = (siteUrl as text, siteId as text) as table =>
    let
        items = GraphAPIHelper[GetAll](
                    "sites/" & siteId
                    & "/lists/Site%20Pages/items"
                    & "?$expand=fields"
                ),
        // Build a flat record field-by-field so there are no Combine/Select
        // conflicts even if AbsoluteUrl, UniqueId, etc. already exist in fields.
        FlattenItem = (item as record) as record =>
        let
            f        = try item[fields] otherwise [],
            // _LikeCount / _CommentCount are SharePoint's internal field names;
            // they return as strings ("5", "") — convert to nullable number.
            likeRaw  = Record.FieldOrDefault(f,    "_LikeCount",    null),
            commRaw  = Record.FieldOrDefault(f,    "_CommentCount", null),
            // Id is lowercase "id" at the item level (not in fields).
            // UniqueId lives in the eTag header as "\"<guid>,<version>\"".
            etagRaw  = Record.FieldOrDefault(item, "eTag",          null)
        in [
            Id                 = Record.FieldOrDefault(item, "id",               null),
            Title              = Record.FieldOrDefault(f,   "Title",             null),
            UniqueId           = if etagRaw = null then null
                                 else Text.BeforeDelimiter(Text.Trim(etagRaw, {""""}), ","),
            LikeCount          = if likeRaw = null or likeRaw = "" then null else try Number.From(likeRaw) otherwise null,
            CommentCount       = if commRaw = null or commRaw = "" then null else try Number.From(commRaw) otherwise null,
            FirstPublishedDate = Record.FieldOrDefault(f,   "Created",           null),
            Modified           = Record.FieldOrDefault(f,   "Modified",          null),
            AbsoluteUrl        = Record.FieldOrDefault(item,"webUrl",            null)
        ],

        flatRows = List.Transform(items, FlattenItem),
        asTable  = if List.Count(flatRows) > 0
                   then Table.FromRecords(flatRows)
                   else #table({"Id","Title","UniqueId","LikeCount","CommentCount",
                                "FirstPublishedDate","Modified","AbsoluteUrl"}, {}),
        withSite = Table.AddColumn(asTable, "SiteUrl", each siteUrl, type text)
    in
        withSite,

    // ── Collect page engagement data across all sites ─────────────────────────
    allPagesTables = List.Transform(siteIdMap, (entry) =>
                         try FetchPageEngagement(entry[SiteUrl], entry[SiteId])
                         otherwise #table(
                             {"UniqueId","AbsoluteUrl","Id","Title",
                              "LikeCount","CommentCount",
                              "FirstPublishedDate","Modified","SiteUrl"}, {})),
    allPages       = Table.Combine(allPagesTables),

    // ── Type engagement columns (guard against columns absent from schema) ─────
    typed = Table.TransformColumnTypes(allPages,
                List.Select(
                    {
                        {"LikeCount",          Int64.Type},
                        {"CommentCount",       Int64.Type},
                        {"FirstPublishedDate", type datetimezone},
                        {"Modified",           type datetimezone}
                    },
                    each Table.HasColumns(allPages, _{0})
                )
            ),

    // ── Rename columns to standard schema ─────────────────────────────────────
    renamed = Table.RenameColumns(typed, {
        {"Id",                 "PageId"},
        {"Title",              "PageTitle"},
        {"AbsoluteUrl",        "PageUrl"},
        {"UniqueId",           "PageUniqueId"},
        {"LikeCount",          "TotalLikes"},
        {"CommentCount",       "TotalComments"},
        {"FirstPublishedDate", "PublishedDate"},
        {"Modified",           "LastModifiedDate"}
    }, MissingField.Ignore),

    // ── Ensure TotalLikes / TotalComments exist before engagement calc ─────────
    withLikes    = if Table.HasColumns(renamed, "TotalLikes")
                   then renamed
                   else Table.AddColumn(renamed, "TotalLikes", each null, Int64.Type),
    withComments = if Table.HasColumns(withLikes, "TotalComments")
                   then withLikes
                   else Table.AddColumn(withLikes, "TotalComments", each null, Int64.Type),

    // ── Add engagement score (weighted index) ─────────────────────────────────
    // Engagement = (Likes × 3) + (Comments × 5)  – adjust weights as needed
    withEngagement = Table.AddColumn(withComments, "EngagementScore",
        each ([TotalLikes] * 3) + ([TotalComments] * 5),
        Int64.Type),

    // ── Add engagement tier ────────────────────────────────────────────────────
    withTier = Table.AddColumn(withEngagement, "EngagementTier", each
        if   [EngagementScore] = null    then "None"
        else if [EngagementScore] >= 100 then "High"
        else if [EngagementScore] >= 25  then "Medium"
        else if [EngagementScore] >  0   then "Low"
        else "None",
        type text),

    // ── Pull sharing activity from Graph API activity report ──────────────────
    // Gives per-user share counts; summarised to tenant-wide totals
    activityRaw = GraphAPIHelper[GetCsv](
                      "getSharePointActivityUserDetail(period='" & ReportPeriod & "')"
                  ),
    activityRenamed = Table.RenameColumns(activityRaw, {
        {"User Principal Name",          "UPN"},
        {"Shared Internally File Count", "FilesSharedInternal"},
        {"Shared Externally File Count", "FilesSharedExternal"}
    }, MissingField.Ignore),
    sharesSummary = Table.Group(
        Table.SelectColumns(activityRenamed,
            {"FilesSharedInternal","FilesSharedExternal"}, MissingField.Ignore),
        {},
        {
            {"TotalSharedInternal", each List.Sum([FilesSharedInternal]), Int64.Type},
            {"TotalSharedExternal", each List.Sum([FilesSharedExternal]), Int64.Type}
        }
    ),

    // ── Final pages result ─────────────────────────────────────────────────────
    result = Table.ReorderColumns(withTier, {
        "PageId", "PageUniqueId", "PageTitle", "PageUrl", "SiteUrl",
        "TotalLikes", "TotalComments", "EngagementScore", "EngagementTier",
        "PublishedDate", "LastModifiedDate"
    }, MissingField.Ignore)

in
    result
