// ============================================================
// 06_UserDemographics.pq
// Graph API – User Activity joined with Azure AD Demographics
//
// Sources:
//   GET /reports/getSharePointActivityUserDetail(period='D30')  → activity
//   GET /v1.0/users?$select=id,displayName,department,...       → demographics
//
// Auth:    Reports.Read.All + User.Read.All
// Notes:
//   - Graph user list is paged (top 999 per call, auto-paginated)
//   - UPN join between activity report and AAD users
//   - PII awareness: UPNs may be obfuscated if tenant Privacy setting
//     "Obfuscated user info" is enabled in M365 Admin Center → Reports
// ============================================================

let
    // ── Unpack parameters ─────────────────────────────────────────────────────
    ReportPeriod = Parameters[ReportPeriod],

    // ── Part A: SharePoint User Activity Detail (CSV) ─────────────────────────
    activityRaw = GraphAPIHelper[GetCsv](
                      "getSharePointActivityUserDetail(period='" & ReportPeriod & "')"
                  ),

    activityRenamed = Table.RenameColumns(activityRaw, {
        {"Report Refresh Date",              "ReportRefreshDate"},
        {"User Principal Name",              "UPN"},
        {"Is Deleted",                       "IsDeleted"},
        {"Deleted Date",                     "DeletedDate"},
        {"Last Activity Date",               "LastActivityDate"},
        {"Viewed Or Edited File Count",      "FilesViewedEdited"},
        {"Synced File Count",                "FilesSynced"},
        {"Shared Internally File Count",     "FilesSharedInternal"},
        {"Shared Externally File Count",     "FilesSharedExternal"},
        {"Visited Page Count",               "PagesVisited"},
        {"Product Assigned",                 "ProductLicenses"},
        {"Report Period",                    "ReportPeriodDays"}
    }, MissingField.Ignore),

    activityTyped = Table.TransformColumnTypes(activityRenamed, {
        {"ReportRefreshDate",    type date},
        {"LastActivityDate",     type date},
        {"FilesViewedEdited",    Int64.Type},
        {"FilesSynced",          Int64.Type},
        {"FilesSharedInternal",  Int64.Type},
        {"FilesSharedExternal",  Int64.Type},
        {"PagesVisited",         Int64.Type},
        {"ReportPeriodDays",     Int64.Type},
        {"IsDeleted",            type logical}
    }),

    // Keep only active users (not deleted, has at least one activity)
    activeUsers = Table.SelectRows(activityTyped, each
        [IsDeleted] <> true
        and ([FilesViewedEdited] > 0 or [PagesVisited] > 0)
    ),

    // ── Part B: Azure AD User Profiles ───────────────────────────────────────
    aadRecords = GraphAPIHelper[GetAll](
                     "users?$select=id,userPrincipalName,displayName,"
                     & "department,jobTitle,city,country,officeLocation,"
                     & "companyName,usageLocation"
                     & "&$top=999"
                 ),

    aadTable   = Table.FromList(aadRecords, Splitter.SplitByNothing(), {"Record"}),
    aadExp     = Table.ExpandRecordColumn(aadTable, "Record", {
                     "id", "userPrincipalName", "displayName",
                     "department", "jobTitle", "city", "country",
                     "officeLocation", "companyName", "usageLocation"
                 }),
    aadRenamed = Table.RenameColumns(aadExp, {
                     {"id",               "UserId"},
                     {"userPrincipalName","UPN"},
                     {"displayName",      "DisplayName"},
                     {"department",       "Department"},
                     {"jobTitle",         "JobTitle"},
                     {"city",             "City"},
                     {"country",          "Country"},
                     {"officeLocation",   "OfficeLocation"},
                     {"companyName",      "CompanyName"},
                     {"usageLocation",    "UsageLocation"}
                 }),

    // Normalise UPN to lowercase for reliable join
    aadNorm    = Table.TransformColumns(aadRenamed, {{"UPN", Text.Lower, type text}}),
    actNorm    = Table.TransformColumns(activeUsers, {{"UPN", Text.Lower, type text}}),

    // ── Part C: Left Join activity → AAD user profiles ────────────────────────
    joined = Table.NestedJoin(
                 actNorm, {"UPN"},
                 aadNorm, {"UPN"},
                 "UserProfile", JoinKind.LeftOuter
             ),
    expanded = Table.ExpandTableColumn(joined, "UserProfile", {
                   "UserId", "DisplayName", "Department", "JobTitle",
                   "City", "Country", "OfficeLocation", "CompanyName"
               }),

    // ── Part D: Classify users with unknown demographics ─────────────────────
    withDeptClean = Table.TransformColumns(expanded, {{
        "Department",
        each if _ = null or _ = "" then "Unknown" else _,
        type text
    }}),

    // ── Part E: Final column order ─────────────────────────────────────────────
    result = Table.ReorderColumns(withDeptClean, {
        "UserId", "UPN", "DisplayName",
        "Department", "JobTitle", "City", "Country", "OfficeLocation",
        "PagesVisited", "FilesViewedEdited", "FilesSynced",
        "FilesSharedInternal", "FilesSharedExternal",
        "LastActivityDate", "ReportRefreshDate", "ReportPeriodDays",
        "ProductLicenses", "IsDeleted"
    }, MissingField.Ignore)

in
    result
