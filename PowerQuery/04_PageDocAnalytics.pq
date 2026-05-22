// ============================================================
// 04_PageDocAnalytics.pq
// Microsoft Graph API – Individual Page and Document Analytics
//
// Sources:
//   Graph API: GET /v1.0/sites/{id}/pages
//   Graph API: GET /v1.0/sites/{id}/drive/items/{itemId}/analytics
//   Graph API: GET /v1.0/sites/{id}/lists/{listId}/items?expand=fields,driveItem
// Scope:   All pages and documents across hub + spoke sites
// Auth:    Sites.Read.All, Files.Read.All
// ============================================================

let
    // ── Unpack parameters ─────────────────────────────────────────────────────
    GraphBaseUrl = Parameters[GraphBaseUrl],
    HubSiteUrl   = Parameters[HubSiteUrl],
    SpokeUrls    = Parameters[SpokeUrls],
    AuthHdr      = GraphAPIHelper[AuthHeader](),

    // ── Helper: fetch all pages for one site via Graph API ──────────────────
    // GET /v1.0/sites/{id}/pages  (requires Sites.Read.All)
    FetchSitePages = (siteUrl as text, siteId as text) as table =>
    let
        items    = GraphAPIHelper[GetAll](
                       "sites/" & siteId & "/pages"
                       & "?$select=id,name,title,webUrl,createdDateTime,"
                       & "lastModifiedDateTime,pageLayout,publishingState"
                   ),
        asTable     = if List.Count(items) > 0
                      then Table.FromRecords(items, MissingField.UseNull)
                      else #table({"id","name","title","webUrl",
                                   "createdDateTime","lastModifiedDateTime",
                                   "pageLayout"}, {}),
        withSite    = Table.AddColumn(asTable,  "SiteId",  each siteId,  type text),
        withSiteUrl = Table.AddColumn(withSite, "SiteUrl", each siteUrl, type text)
    in
        withSiteUrl,

    // ── Helper: fetch all documents from a site's document library ────────────
    FetchSiteDocs = (siteUrl as text, siteId as text) as table =>
    let
        // Get default drive root children (Shared Documents / root library)
        endpoint = GraphBaseUrl & "/sites/" & siteId
                   & "/drive/root/children"
                   & "?$select=id,name,webUrl,size,createdDateTime,"
                   & "lastModifiedDateTime,file,parentReference"
                   & "&$top=500",
        items    = GraphAPIHelper[GetAll](
                       "sites/" & siteId & "/drive/root/children"
                       & "?$select=id,name,webUrl,size,createdDateTime,"
                       & "lastModifiedDateTime,file,parentReference"
                   ),
        asTable  = Table.FromList(items, Splitter.SplitByNothing(), {"Record"}),
        expanded = if Table.RowCount(asTable) > 0
                   then Table.ExpandRecordColumn(asTable, "Record",
                            {"id", "name", "webUrl", "size",
                             "createdDateTime", "lastModifiedDateTime", "file"})
                   else #table(
                            {"id", "name", "webUrl", "size",
                             "createdDateTime", "lastModifiedDateTime", "file"}, {}),
        // Keep only actual files (not folders)
        filesOnly = Table.SelectRows(expanded, each [file] <> null),
        withSite  = Table.AddColumn(filesOnly, "SiteId",       each siteId,  type text),
        withUrl   = Table.AddColumn(withSite,  "SiteUrl",      each siteUrl, type text),
        withType  = Table.AddColumn(withUrl,   "ContentType",  each "Document", type text)
    in
        withType,

    // ── Resolve site IDs for all News Online sites ─────────────────────────────
    allSiteUrls = List.Combine({{HubSiteUrl}, SpokeUrls}),

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
                          ManualStatusHandling = {404}]
                     ),
        parsed     = Json.Document(raw)
    in
        [SiteUrl = siteUrl, SiteId = Record.FieldOrDefault(parsed, "id", "")],

    siteIdMap   = List.Transform(allSiteUrls, ResolveSiteId),

    // ── Collect all pages ─────────────────────────────────────────────────────
    allPageTables = List.Transform(siteIdMap, each
                        FetchSitePages(_[SiteUrl], _[SiteId])),
    combinedPages = Table.Combine(allPageTables),

    // ── Collect all documents ─────────────────────────────────────────────────
    allDocTables  = List.Transform(siteIdMap, each
                        FetchSiteDocs(_[SiteUrl], _[SiteId])),
    combinedDocs  = Table.Combine(allDocTables),

    // ── Normalise columns so pages and docs can be unioned ─────────────────────
    pagesNorm = Table.SelectColumns(
        Table.RenameColumns(combinedPages, {
            {"id",                   "ItemId"},
            {"title",                "ItemTitle"},
            {"webUrl",               "ItemUrl"},
            {"name",                 "FileName"},
            {"pageLayout",           "ContentType"},
            {"createdDateTime",      "CreatedDateTime"},
            {"lastModifiedDateTime", "LastModifiedDateTime"}
        }, MissingField.Ignore),
        {"ItemId","ItemTitle","ItemUrl","FileName","ContentType",
         "SiteId","SiteUrl","CreatedDateTime","LastModifiedDateTime"},
        MissingField.UseNull
    ),
    pagesWithKind = Table.AddColumn(pagesNorm, "ItemKind", each "Page", type text),

    docsNorm = Table.SelectColumns(
        Table.AddColumn(
            Table.RenameColumns(combinedDocs, {
                {"id",                   "ItemId"},
                {"name",                 "ItemTitle"},
                {"webUrl",               "ItemUrl"},
                {"createdDateTime",      "CreatedDateTime"},
                {"lastModifiedDateTime", "LastModifiedDateTime"}
            }, MissingField.Ignore),
            "FileName", each [ItemTitle], type text
        ),
        {"ItemId","ItemTitle","ItemUrl","FileName","ContentType",
         "SiteId","SiteUrl","CreatedDateTime","LastModifiedDateTime"},
        MissingField.UseNull
    ),
    docsWithKind = Table.AddColumn(docsNorm, "ItemKind", each "Document", type text),

    // ── Union pages + documents ───────────────────────────────────────────────
    allItems = Table.Combine({pagesWithKind, docsWithKind}),

    // ── Type final columns ────────────────────────────────────────────────────
    typed = Table.TransformColumnTypes(allItems, {
        {"CreatedDateTime",      type datetimezone},
        {"LastModifiedDateTime", type datetimezone}
    }),

    result = Table.ReorderColumns(typed, {
        "ItemId", "ItemKind", "ItemTitle", "FileName",
        "ContentType", "ItemUrl",
        "SiteId", "SiteUrl",
        "CreatedDateTime", "LastModifiedDateTime"
    }, MissingField.Ignore)

in
    result
