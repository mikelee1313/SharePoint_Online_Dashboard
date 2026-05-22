// ============================================================
// 02_SiteOverview.pq
// Graph API – SharePoint Site Usage Detail
//
// Source:  GET /reports/getSharePointSiteUsageDetail(period='D30')
// Scope:   All SharePoint sites in the tenant (filtered to News Online)
// Refresh: 24–48 hour latency (Microsoft backend processing)
// ============================================================

let
    // ── Unpack parameters ─────────────────────────────────────────────────────
    ReportPeriod = Parameters[ReportPeriod],
    HubSiteUrl   = Parameters[HubSiteUrl],
    SpokeUrls    = Parameters[SpokeUrls],
    GraphBaseUrl = Parameters[GraphBaseUrl],
    AuthHdr      = GraphAPIHelper[AuthHeader](),

    // ── Build SiteCollectionGuid → {SiteUrl, SiteType} lookup ────────────────
    // Resolves each configured URL via GET /sites/{hostname}:/{path} so we can
    // filter and enrich usage data even when the Reports API omits Site URLs.
    ResolveSiteEntry = (siteUrl as text, siteType as text) as record =>
    let
        uri      = Uri.Parts(siteUrl),
        hostname = uri[Host],
        relPath  = Text.TrimStart(uri[Path], "/"),
        raw      = Web.Contents(
                       GraphBaseUrl & "/sites/" & hostname & ":/" & relPath,
                       [Headers              = Record.Combine({[#"Content-Type" = "application/json"], AuthHdr}),
                        ManualStatusHandling = {400, 401, 403, 404, 500}]
                   ),
        parsed   = Json.Document(raw),
        graphId  = Record.FieldOrDefault(parsed, "id", ""),
        // Graph site id format: "hostname,siteCollectionGuid,webGuid"
        siteGuid = Text.Lower(
                       if Text.Contains(graphId, ",")
                       then Text.Split(graphId, ","){ 1 }
                       else graphId
                   )
    in
        [SiteGuid = siteGuid, SiteUrl = siteUrl, SiteType = siteType],

    allEntries   = List.Combine({
                       {{HubSiteUrl, "Hub"}},
                       List.Transform(SpokeUrls, (u) => {u, "Spoke"})
                   }),
    resolvedList = List.Transform(allEntries, (pair) =>
                       try ResolveSiteEntry(pair{0}, pair{1})
                       otherwise [SiteGuid = "", SiteUrl = pair{0}, SiteType = "Unknown"]),
    siteMap      = Table.FromRecords(
                       List.Select(resolvedList, each _[SiteGuid] <> ""),
                       type table [SiteGuid = text, SiteUrl = text, SiteType = text]
                   ),
    siteGuids    = siteMap[SiteGuid],

    // ── Pull raw CSV from Graph API reports endpoint ──────────────────────────
    rawTable = GraphAPIHelper[GetCsv](
                   "getSharePointSiteUsageDetail(period='" & ReportPeriod & "')"
               ),

    // ── Rename to clean column names ──────────────────────────────────────────
    renamed = Table.RenameColumns(rawTable, {
        {"Report Refresh Date",          "ReportRefreshDate"},
        {"Site URL",                     "SiteUrl"},
        {"Site Id",                      "SiteId"},
        {"Is Deleted",                   "IsDeleted"},
        {"Last Activity Date",           "LastActivityDate"},
        {"File Count",                   "FileCount"},
        {"Active File Count",            "ActiveFileCount"},
        {"Page View Count",              "PageViewCount"},
        {"Visited Page Count",           "VisitedPageCount"},
        {"Storage Used (Byte)",          "StorageUsedBytes"},
        {"Storage Allocated (Byte)",     "StorageAllocatedBytes"},
        {"Root Web Template",            "SiteTemplate"},
        {"Owner Display Name",           "OwnerDisplayName"},
        {"Owner Principal Name",         "OwnerPrincipalName"},
        {"Report Period",                "ReportPeriodDays"}
    }, MissingField.Ignore),

    // ── Normalise SiteId to lowercase GUID for joining ────────────────────────
    // Report SiteId may be wrapped in curly braces; strip them for comparison.
    withGuid = Table.AddColumn(renamed, "_SiteGuid",
                   each if [SiteId] = null then ""
                        else Text.Lower(Text.Replace(Text.Replace([SiteId], "{", ""), "}", "")),
                   type text),

    // ── Filter to News Online sites by SiteId match ───────────────────────────
    // SiteId-based filtering works even when the Site URL column is blank.
    filtered = Table.SelectRows(withGuid, each List.Contains(siteGuids, [_SiteGuid])),

    // ── Replace blank report SiteUrl with resolved URL + SiteType from siteMap ─
    withoutBlankUrl = Table.RemoveColumns(filtered, {"SiteUrl"}),
    joined          = Table.NestedJoin(withoutBlankUrl, "_SiteGuid",
                                       siteMap, "SiteGuid", "_SiteInfo", JoinKind.LeftOuter),
    expanded        = Table.ExpandTableColumn(joined, "_SiteInfo", {"SiteUrl", "SiteType"}),
    withoutHelper   = Table.RemoveColumns(expanded, {"_SiteGuid"}),

    // ── Type conversions ─────────────────────────────────────────────────────
    typed = Table.TransformColumnTypes(withoutHelper, {
        {"ReportRefreshDate",     type date},
        {"LastActivityDate",      type date},
        {"IsDeleted",             type logical},
        {"FileCount",             Int64.Type},
        {"ActiveFileCount",       Int64.Type},
        {"PageViewCount",         Int64.Type},
        {"VisitedPageCount",      Int64.Type},
        {"StorageUsedBytes",      Int64.Type},
        {"StorageAllocatedBytes", Int64.Type},
        {"ReportPeriodDays",      Int64.Type}
    }),

    // ── Derived columns ───────────────────────────────────────────────────────
    withStorageMB = Table.AddColumn(typed, "StorageUsedMB",
                        each Number.Round([StorageUsedBytes] / 1048576, 2),
                        type number),

    // ── Extract site name from URL ────────────────────────────────────────────
    withSiteName = Table.AddColumn(withStorageMB, "SiteName", each
        let
            parts = Text.Split([SiteUrl], "/"),
            last  = List.Last(parts)
        in if last = "" then List.Last(List.RemoveLastN(parts, 1)) else last,
        type text),

    // ── Remove rows with no activity (IsDeleted = true or null SiteId) ────────
    clean = Table.SelectRows(withSiteName, each
        [IsDeleted] <> true and [SiteId] <> null and [SiteId] <> ""),

    // ── Final column order ─────────────────────────────────────────────────────
    result = Table.ReorderColumns(clean, {
        "SiteId", "SiteName", "SiteUrl", "SiteType",
        "ReportRefreshDate", "LastActivityDate",
        "PageViewCount", "VisitedPageCount",
        "FileCount", "ActiveFileCount",
        "StorageUsedBytes", "StorageUsedMB", "StorageAllocatedBytes",
        "OwnerDisplayName", "OwnerPrincipalName",
        "SiteTemplate", "IsDeleted", "ReportPeriodDays"
    }, MissingField.Ignore)

in
    result
