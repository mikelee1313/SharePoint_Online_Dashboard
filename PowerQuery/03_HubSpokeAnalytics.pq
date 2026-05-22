// ============================================================
// 03_HubSpokeAnalytics.pq
// Per-site analytics using Microsoft Graph Sites Analytics API
//
// Source:  GET /v1.0/sites/{site-id}/analytics/allTime
//          GET /v1.0/sites/{site-id}/analytics/lastSevenDays
// Scope:   Individual site-level activity stats for hub + each spoke
// Auth:    Requires Sites.Read.All
// ============================================================

let
    // ── Unpack parameters ─────────────────────────────────────────────────────
    GraphBaseUrl = Parameters[GraphBaseUrl],
    HubSiteUrl   = Parameters[HubSiteUrl],
    SpokeUrls    = Parameters[SpokeUrls],
    AuthHdr      = GraphAPIHelper[AuthHeader](),

    // ── Build the list of all site URLs to query (hub + spokes) ──────────────
    allSiteUrls = List.Combine({{HubSiteUrl}, SpokeUrls}),

    // ── Step 1: Resolve each site URL → Graph site ID ─────────────────────────
    // Graph API: GET /v1.0/sites/{hostname}:/{server-relative-path}
    ResolveSiteId = (siteUrl as text) as record =>
    let
        uri        = Uri.Parts(siteUrl),
        hostname   = uri[Host],
        scheme     = uri[Scheme],
        // Step 1: strip scheme://hostname prefix
        hostPrefix = scheme & "://" & hostname,
        afterHost  = Text.TrimStart(
                         if Text.StartsWith(siteUrl, hostPrefix)
                         then Text.Range(siteUrl, Text.Length(hostPrefix))
                         else uri[Path],
                         "/"),
        // Step 2: if what remains is still a full URL (malformed double-URL from Parameters),
        // extract just the server-relative path from it
        relPath    = Text.TrimStart(
                         if Text.StartsWith(Text.Lower(afterHost), "https://") or
                            Text.StartsWith(Text.Lower(afterHost), "http://")
                         then Uri.Parts(afterHost)[Path]
                         else afterHost,
                         "/"),
        endpoint   = "sites/" & hostname & ":/" & relPath,
        directUrl  = GraphBaseUrl & "/" & endpoint,
        raw       = Web.Contents(directUrl, [
                        Headers              = Record.Combine({[#"Content-Type" = "application/json"], AuthHdr}),
                        ManualStatusHandling = {403, 404}
                    ]),
        parsed    = Json.Document(raw)
    in
        [
            SiteId       = Record.FieldOrDefault(parsed, "id",          ""),
            SiteName     = Record.FieldOrDefault(parsed, "displayName", siteUrl),
            SiteUrl      = siteUrl,
            WebUrl       = Record.FieldOrDefault(parsed, "webUrl",      siteUrl),
            CreatedDate  = Record.FieldOrDefault(parsed, "createdDateTime", null),
            LastModified = Record.FieldOrDefault(parsed, "lastModifiedDateTime", null)
        ],

    // ── Step 2: For each resolved site, fetch analytics stats ─────────────────
    FetchSiteAnalytics = (siteId as text, siteName as text, siteUrl as text) as record =>
    let
        // All-time analytics
        allTimeUrl  = GraphBaseUrl & "/sites/" & siteId & "/analytics/allTime",
        allTimeRaw  = Web.Contents(allTimeUrl, [
                          Headers              = Record.Combine({[#"Content-Type" = "application/json"], AuthHdr}),
                          ManualStatusHandling = {403, 404}
                      ]),
        allTimeJson = Json.Document(allTimeRaw),
        atAccess    = Record.FieldOrDefault(allTimeJson, "access",    []),
        atViews     = Record.FieldOrDefault(atAccess,   "actionCount", 0),
        atActors    = Record.FieldOrDefault(atAccess,   "actorCount",  0),

        // Last 7 days analytics
        last7Url    = GraphBaseUrl & "/sites/" & siteId & "/analytics/lastSevenDays",
        last7Raw    = Web.Contents(last7Url, [
                          Headers              = Record.Combine({[#"Content-Type" = "application/json"], AuthHdr}),
                          ManualStatusHandling = {403, 404}
                      ]),
        last7Json   = Json.Document(last7Raw),
        l7Access    = Record.FieldOrDefault(last7Json,  "access",      []),
        l7Views     = Record.FieldOrDefault(l7Access,   "actionCount", 0),
        l7Actors    = Record.FieldOrDefault(l7Access,   "actorCount",  0)
    in
        [
            SiteId           = siteId,
            SiteName         = siteName,
            SiteUrl          = siteUrl,
            AllTimeViews     = atViews,
            AllTimeActors    = atActors,
            Last7DaysViews   = l7Views,
            Last7DaysActors  = l7Actors
        ],

    // ── Step 3: Combine – resolve IDs then fetch analytics ────────────────────
    siteMeta    = List.Transform(allSiteUrls, ResolveSiteId),
    analytics   = List.Transform(siteMeta, each
                      FetchSiteAnalytics(_[SiteId], _[SiteName], _[SiteUrl])),

    // Merge metadata + analytics into one record list
    merged = List.Transform(
        List.Zip({siteMeta, analytics}),
        each Record.Combine(_)
    ),

    // ── Step 4: Convert to table ──────────────────────────────────────────────
    asTable  = Table.FromRecords(merged, type table [
        SiteId           = nullable text,
        SiteName         = nullable text,
        SiteUrl          = nullable text,
        WebUrl           = nullable text,
        CreatedDate      = nullable text,
        LastModified     = nullable text,
        AllTimeViews     = nullable number,
        AllTimeActors    = nullable number,
        Last7DaysViews   = nullable number,
        Last7DaysActors  = nullable number
    ], MissingField.UseNull),

    // ── Step 5: Classify hub vs spoke ────────────────────────────────────────
    withType = Table.AddColumn(asTable, "SiteType", each
        if Text.Lower([SiteUrl]) = Text.Lower(HubSiteUrl) then "Hub" else "Spoke",
        type text),

    // ── Step 6: Parse dates ──────────────────────────────────────────────────
    typed = Table.TransformColumnTypes(withType, {
        {"CreatedDate",     type datetimezone},
        {"LastModified",    type datetimezone},
        {"AllTimeViews",    Int64.Type},
        {"AllTimeActors",   Int64.Type},
        {"Last7DaysViews",  Int64.Type},
        {"Last7DaysActors", Int64.Type}
    }),

    // ── Step 7: Final sort by all-time views descending ──────────────────────
    result = Table.Sort(typed, {{"AllTimeViews", Order.Descending}})

in
    result
