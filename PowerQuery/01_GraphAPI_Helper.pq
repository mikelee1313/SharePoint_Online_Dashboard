// ============================================================
// 01_GraphAPI_Helper.pq
// Reusable helper function for paginated Microsoft Graph API calls
//
// Returns a combined table from all pages of a Graph API endpoint.
// Usage:
//   let result = fnGraphGetAll("sites?$select=id,displayName,webUrl") in result
// ============================================================

let
    // ── Unpack parameters ─────────────────────────────────────────────────────
    GraphBaseUrl = Parameters[GraphBaseUrl],
    TenantId     = Parameters[TenantId],
    ClientId     = Parameters[ClientId],
    ClientSecret = Parameters[ClientSecret],

    // ── Acquire an app-only Bearer token (client credentials flow) ────────────
    // Calls: POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
    // Set credentials for login.microsoftonline.com to "Anonymous" in
    // Power BI Desktop → Data source settings.
    GetAccessToken = () as text =>
    let
        tokenUrl  = "https://login.microsoftonline.com/" & TenantId & "/oauth2/v2.0/token",
        body      = "grant_type=client_credentials"
                    & "&client_id="     & Uri.EscapeDataString(ClientId)
                    & "&client_secret=" & Uri.EscapeDataString(ClientSecret)
                    & "&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default",
        response  = Web.Contents(tokenUrl, [
                        Headers = [#"Content-Type" = "application/x-www-form-urlencoded"],
                        Content = Text.ToBinary(body),
                        ManualStatusHandling = {400, 401, 403}
                    ]),
        parsed    = Json.Document(response),
        token     = parsed[access_token]
    in
        token,

    // ── Build auth header record using a fresh token ──────────────────────────
    AuthHeader = () as record =>
        [ #"Authorization" = "Bearer " & GetAccessToken() ],

    fnGraphGetAll = (relativeUrl as text, optional extraHeaders as record) as list =>
    let
        baseUrl     = GraphBaseUrl & "/" & relativeUrl,
        defaultHdrs = Record.Combine({
            [
                #"Content-Type"     = "application/json",
                #"Accept"           = "application/json",
                #"ConsistencyLevel" = "eventual"
            ],
            AuthHeader()
        }),
        mergedHdrs  = if extraHeaders <> null
                      then Record.Combine({defaultHdrs, extraHeaders})
                      else defaultHdrs,

        // Fetch one page, return {records, nextLink}
        FetchPage = (url as text) as record =>
        let
            rawBytes = Web.Contents(url, [
                Headers           = mergedHdrs,
                ManualStatusHandling = {400, 403, 404, 429, 500, 503}
            ]),
            parsed   = Json.Document(rawBytes),
            records  = if Record.HasFields(parsed, "value")
                       then parsed[value]
                       else {},
            nextLink = Record.FieldOrDefault(parsed, "@odata.nextLink", null)
        in
            [Records = records, NextLink = nextLink],

        // Walk all pages, accumulate records
        GetAllPages = (startUrl as text, acc as list) as list =>
        let
            page   = FetchPage(startUrl),
            newAcc = List.Combine({acc, page[Records]}),
            result = if page[NextLink] <> null
                     then @GetAllPages(page[NextLink], newAcc)
                     else newAcc
        in
            result,

        allRecords = GetAllPages(baseUrl, {})
    in
        allRecords,

    // -------------------------------------------------------
    // fnGraphGetCsv – helper for Graph Reports API
    // (reports endpoints return CSV, not JSON)
    // -------------------------------------------------------
    fnGraphGetCsv = (reportPath as text) as table =>
    let
        url      = GraphBaseUrl & "/reports/" & reportPath,
        rawBytes = Web.Contents(url, [
            Headers = Record.Combine({[ #"Accept" = "text/csv" ], AuthHeader()})
        ]),
        csv      = Csv.Document(rawBytes, [
            Delimiter  = ",",
            Encoding   = 65001,   // UTF-8
            QuoteStyle = QuoteStyle.Csv
        ]),
        promoted = Table.PromoteHeaders(csv, [PromoteAllScalars = true])
    in
        promoted

in
    [
        GetAll      = fnGraphGetAll,
        GetCsv      = fnGraphGetCsv,
        AuthHeader  = AuthHeader
    ]
