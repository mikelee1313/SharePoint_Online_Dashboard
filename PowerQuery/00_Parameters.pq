// ============================================================
// 00_Parameters.pq
// Power BI Parameter Queries for Contoso News Online Analytics
//
// INSTRUCTIONS:
//   Load this as a single query named "Parameters" in Power BI Desktop.
//   Reference values in other queries using: Parameters[TenantId], etc.
//
//   To use individual named parameters instead, split each field into
//   its own query (Manage Parameters dialog or blank query).
// ============================================================
let
    // Azure AD Tenant GUID
    // Example: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    TenantId = "YOUR-TENANT-ID-HERE",

    // Your M365 tenant short name (part before .onmicrosoft.com)
    TenantName = "contoso",

    // Full URL of the News Online Hub site (no trailing slash)
    HubSiteUrl = "https://contoso.sharepoint.com/sites/NewsOnline",

    // Microsoft Graph API report period window
    // Allowed: "D7" | "D30" | "D90" | "D180"
    ReportPeriod = "D30",

    // Azure AD App Registration Client (Application) ID
    // Example: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    ClientId = "YOUR-CLIENT-ID-HERE",

    // Azure AD App Registration Client Secret
    // Generate in: Azure Portal → App registrations → your app → Certificates & secrets
    ClientSecret = "YOUR-CLIENT-SECRET-HERE",

    // Full URLs of all spoke sites under the News Online hub
    TenantBase = "https://contoso.sharepoint.com/",
    SpokePaths = {
        "sites/NewsOnline-Finance",
        "sites/NewsOnline-HR",
        "sites/NewsOnline-Legal",
        "sites/NewsOnline-Operations",
        "sites/NewsOnline-Technology",
        "sites/NewsOnline-Marketing"
    },
    SpokeUrls = List.Transform(SpokePaths, each TenantBase & _),

    // Microsoft Graph base URL (do not edit)
    GraphBaseUrl = "https://graph.microsoft.com/v1.0"
in
    [
        TenantId     = TenantId,
        TenantName   = TenantName,
        HubSiteUrl   = HubSiteUrl,
        ReportPeriod = ReportPeriod,
        ClientId     = ClientId,
        ClientSecret = ClientSecret,
        SpokeUrls    = SpokeUrls,
        GraphBaseUrl = GraphBaseUrl
    ]
