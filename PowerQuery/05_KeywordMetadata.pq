// ============================================================
// 05_KeywordMetadata.pq
// Microsoft Graph Search API – Content Metadata & Keyword Reporting
//
// Source:  POST https://graph.microsoft.com/v1.0/search/query
// Scope:   Pages and documents across News Online matching tracked keywords
// Auth:    Sites.Read.All (client credentials via GraphAPIHelper)
//
// Prerequisites:
//   - Managed properties must be CRAWLED & INDEXED in SharePoint admin
//   - To expose custom metadata: SharePoint Admin → Search → Manage Properties
//     Common managed props: RefinableString00–49, owstaxIdMetadataAllTagsInfo
//
// Usage:   Adjust KeywordsToTrack and FieldsToFetch to match Contoso's
//          custom site columns / content types in News Online.
// ============================================================

let
    // ── Unpack parameters ─────────────────────────────────────────────────────
    HubSiteUrl   = Parameters[HubSiteUrl],
    GraphBaseUrl = Parameters[GraphBaseUrl],
    AuthHdr      = GraphAPIHelper[AuthHeader](),

    // ── Configuration – adjust to Contoso's metadata taxonomy ──────────────────
    // Add or remove keywords that represent content topics in News Online
    KeywordsToTrack = {
        "benefits",
        "policy",
        "announcement",
        "leadership",
        "technology",
        "compliance",
        "diversity",
        "community",
        "recognition",
        "strategy"
    },

    // SharePoint field internal names to retrieve per search result.
    // These must be configured as Retrievable in SharePoint Search admin.
    // Note: ViewsLifeTime / ViewsRecent require analytics managed properties.
    FieldsToFetch = {
        "title",
        "contentType",
        "author",
        "createdDateTime",
        "lastModifiedDateTime",
        "owstaxIdMetadataAllTagsInfo",  // taxonomy tags
        "RefinableString00",            // custom metadata field 1
        "RefinableString01",            // custom metadata field 2
        "ViewsLifeTime",                // lifetime view count (if indexed)
        "ViewsRecent"                   // recent view count (if indexed)
    },

    // ── Helper: run one keyword search via Graph Search API ──────────────────
    // POST /v1.0/search/query  –  entityTypes: listItem covers pages & docs
    SearchKeyword = (keyword as text) as table =>
    let
        searchBodyRecord = [
            requests = {[
                entityTypes = {"listItem"},
                query       = [ queryString = keyword & " Path:""" & HubSiteUrl & """" ],
                fields      = FieldsToFetch,
                size        = 500
            ]}
        ],

        rawResponse = Web.Contents(
            GraphBaseUrl & "/search/query",
            [
                Headers              = Record.Combine({
                                           [#"Content-Type" = "application/json"],
                                           AuthHdr
                                       }),
                Content              = Json.FromValue(searchBodyRecord),
                ManualStatusHandling = {400, 403, 500}
            ]
        ),

        parsed         = Json.Document(rawResponse),
        responses      = try parsed[value]                            otherwise {},
        firstResponse  = if List.Count(responses) > 0 then responses{0} else [],
        containers     = try firstResponse[hitsContainers]            otherwise {},
        firstContainer = if List.Count(containers) > 0 then containers{0} else [],
        hits           = try firstContainer[hits]                     otherwise {},

        // Flatten each hit: inject webUrl as Path, then merge with fields record
        FlattenHit = (hit as record) as record =>
        let
            resource = try hit[resource]          otherwise [],
            fields   = try resource[fields]       otherwise [],
            extra    = [ Path = Record.FieldOrDefault(resource, "webUrl", null) ]
        in
            Record.Combine({extra, fields}),

        flatRows = List.Transform(hits, FlattenHit),
        asTable  = if List.Count(flatRows) > 0
                   then Table.FromRecords(flatRows, MissingField.UseNull)
                   else #table({"title","Path","contentType"}, {}),

        // Derive SiteName from URL: https://tenant/sites/<SiteName>/...
        withSiteName = Table.AddColumn(asTable, "SiteName",
                           each try Text.Split([Path], "/"){4} otherwise null,
                           type text),

        withKeyword = Table.AddColumn(withSiteName, "SearchKeyword",
                          each keyword, type text)
    in
        withKeyword,

    // ── Run all keyword searches ──────────────────────────────────────────────
    keywordResults = List.Transform(KeywordsToTrack, SearchKeyword),
    combined       = Table.Combine(keywordResults),

    // ── Rename Graph field names to report-friendly column names ──────────────
    renamed = Table.RenameColumns(combined, {
        {"title",                       "PageTitle"},
        {"Path",                        "PageUrl"},
        {"SiteName",                    "SiteName"},
        {"contentType",                 "ContentType"},
        {"author",                      "AuthorEmail"},
        {"lastModifiedDateTime",        "LastModified"},
        {"createdDateTime",             "CreatedDate"},
        {"owstaxIdMetadataAllTagsInfo", "TaxonomyTags"},
        {"RefinableString00",           "CustomMetadata1"},
        {"RefinableString01",           "CustomMetadata2"},
        {"ViewsLifeTime",               "ViewsLifetime"},
        {"ViewsRecent",                 "ViewsLast30Days"}
    }, MissingField.Ignore),

    // ── Parse view counts to numeric (guard against missing columns) ──────────
    typed = Table.TransformColumnTypes(
        renamed,
        List.Select(
            {{"ViewsLifetime", Int64.Type}, {"ViewsLast30Days", Int64.Type}},
            each Table.HasColumns(renamed, _{0})
        )
    ),

    // ── Ensure view count columns always exist (default 0 if SP managed property not indexed) ──
    withViewDefaults =
        let
            t1 = if Table.HasColumns(typed, "ViewsLifetime")
                 then typed
                 else Table.AddColumn(typed, "ViewsLifetime", each 0, Int64.Type),
            t2 = if Table.HasColumns(t1, "ViewsLast30Days")
                 then t1
                 else Table.AddColumn(t1, "ViewsLast30Days", each 0, Int64.Type)
        in t2,

    // ── Remove duplicate paths – keep row with highest ViewsLifetime ──────────
    sorted  = Table.Sort(withViewDefaults,
                  List.Select(
                      {{"ViewsLifetime", Order.Descending}, {"PageUrl", Order.Ascending}},
                      each Table.HasColumns(withViewDefaults, _{0})
                  )),
    deduped = Table.Distinct(sorted, {"PageUrl", "SearchKeyword"}),

    result = Table.ReorderColumns(deduped, {
        "SearchKeyword", "PageTitle", "PageUrl", "SiteName",
        "ContentType", "AuthorEmail", "CreatedDate", "LastModified",
        "TaxonomyTags", "CustomMetadata1", "CustomMetadata2",
        "ViewsLifetime", "ViewsLast30Days"
    }, MissingField.Ignore)

in
    result
