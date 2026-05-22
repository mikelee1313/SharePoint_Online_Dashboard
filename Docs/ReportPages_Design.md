# Report Pages Design – Contoso News Online Analytics

## Page 1 – Executive Summary

**Purpose:** Leadership snapshot. All KPIs at a glance.

| Visual | Type | Measure | Notes |
|--------|------|---------|-------|
| Total Page Views | Card | `[Total Page Views]` | Period from slicer |
| Active Users | Card | `[Total Active Users]` | Last 30 days |
| Active Sites | Card | `[Active Sites Count]` | Sites with > 0 views |
| Engagement Rate | Card | `[Engagement Rate]` | % pages with reactions |
| Views Trend | Line chart | `[Total Page Views]` by `DateTable[Date]` | Weekly granularity |
| Top 10 Sites | Bar chart | `[Total Page Views]` by `SiteOverview[SiteName]` | Sorted desc |
| Hub vs Spoke | Donut | `[Hub Page Views]`, `[Spoke Page Views]` | |
| MoM Change | Card | `[Page Views MoM % Change]` with conditional format | ▲/▼ indicator |
| Date Slicer | Relative slicer | `DateTable[Date]` | Default: last 30 days |

**Filters (report-level):** DateTable[IsLast30Days]

---

## Page 2 – Site Overview

**Purpose:** Full site inventory with usage metrics per site.

| Visual | Type | Fields | Notes |
|--------|------|--------|-------|
| Site Matrix | Matrix | Rows: SiteName, SiteType; Cols: Views, Active Files, Storage GB, Last Activity | Conditional formatting on views |
| Storage Chart | Clustered bar | Storage Used GB by Site | Color by SiteType |
| Site Activity Map | Map (if location available) | Bubble by site visits | Requires lat/long or city |
| Stale Sites | Table | Sites with no activity in 30+ days | Filter: LastActivityDate < TODAY()-30 |

**Drillthrough:** → Page 3 (Hub & Spoke Breakdown) by SiteId

---

## Page 3 – Hub & Spoke Breakdown

**Purpose:** Visualize the hub-and-spoke hierarchy and compare performance.

| Visual | Type | Fields | Notes |
|--------|------|--------|-------|
| Spoke Comparison | Horizontal bar | `[Total Page Views]` by SiteName, colored by SiteType | Hub pinned to top |
| Treemap | Treemap | `[Total Page Views]` by SiteName, grouped by SiteType | Hub = distinct color |
| Spoke KPI Table | Table | SiteName, Views, Active Files, Last Activity, Storage | Sortable |
| Drillthrough target | Table | All metrics for selected site | Activated from Page 2 |

**Navigation:** Breadcrumb button → Executive Summary

---

## Page 4 – Page & Document Analytics

**Purpose:** Most viewed/created content across all News Online sites.

| Visual | Type | Fields | Notes |
|--------|------|--------|-------|
| Top Pages | Table | ItemTitle, SiteName, ItemKind, CreatedDateTime, LastModifiedDateTime | Top 50, sorted by lastModified |
| Content by Type | Donut | Count by ItemKind (Page/Document), ContentType | |
| Publication Trend | Area chart | Pages Published by week (CreatedDateTime) | Requires DateTable join |
| Stale Content | Table | Items not modified in 90+ days | Filter: LastModifiedDateTime < TODAY()-90 |
| Search/Filter | Slicer | SiteUrl, ItemKind, ContentType | |

---

## Page 5 – Content Metadata / Keywords

**Purpose:** Understand which topics drive the most traffic and engagement.

| Visual | Type | Fields | Notes |
|--------|------|--------|-------|
| Keyword Bar | Bar chart | `[Total Lifetime Views (Keyword)]` by SearchKeyword | Sorted desc |
| Tag Cloud | Custom visual (Word Cloud) | SearchKeyword sized by ViewsLifetime | Requires AppSource visual |
| Keyword Trend | Line chart | ViewsLast30Days by SearchKeyword | Multi-line |
| Top Pages per Keyword | Matrix | Rows: SearchKeyword; Cols: PageTitle, ViewsLifetime | Expand/collapse |
| Custom Metadata Filter | Slicer | CustomMetadata1, CustomMetadata2, TaxonomyTags | Multi-select |

**Notes:** Keyword list is configurable in `05_KeywordMetadata.pq`. Add/remove topics to match Contoso taxonomy.

---

## Page 6 – User Demographics

**Purpose:** Understand who is engaging with News Online by department, role, and location.

| Visual | Type | Fields | Notes |
|--------|------|--------|-------|
| Active Users by Department | Horizontal bar | `[Active Users by Department]` by Department | Top 15 |
| Activity by Job Title | Treemap | `[Total Pages Visited]` by JobTitle | |
| Geographic Distribution | Map | Active users by City | Bubble size = user count |
| Top Users | Table | DisplayName, Department, JobTitle, PagesVisited, FilesViewedEdited | **Obfuscate if privacy policy requires** |
| Department KPIs | Matrix | Department, ActiveUsers, TotalPageViews, AvgPagesPerUser | |
| Activity Heatmap | Matrix | DayName (rows) × MonthShort (cols), values = [Total Pages Visited] | |

**Privacy Note:** Individual user data (UPNs, names) should be restricted to HR/Leadership roles via Row-Level Security (RLS). See RLS section below.

---

## Page 7 – Engagement (Likes & Shares)

**Purpose:** Measure content resonance through reactions and sharing behaviour.

| Visual | Type | Fields | Notes |
|--------|------|--------|-------|
| Top Liked Pages | Table | PageTitle, SiteUrl, TotalLikes, TotalComments, EngagementScore, EngagementTier | Top 20 |
| Engagement Tier | Donut | Count by EngagementTier (High/Medium/Low/None) | |
| Likes Trend | Line chart | TotalLikes by PublishedDate (monthly) | |
| Engagement Score | Bar | EngagementScore by PageTitle | Top 15 |
| Pages with No Engagement | KPI | `[Pages with Likes]` / `[Total Pages]` | % engaged |
| Site Engagement Comparison | Bar | `[Total Engagement Score]` by SiteUrl | Hub vs spokes |

---

## Page 8 – Date Range Slicer (Cross-Page)

**Purpose:** Provide flexible date filtering that syncs across all pages via sync slicers.

| Visual | Type | Fields | Notes |
|--------|------|--------|-------|
| Relative Date Slicer | Slicer | DateTable[Date], relative mode | Default: last 30 days |
| Custom Date Range | Slicer | DateTable[Date], between mode | |
| Period Buttons | Buttons | Bookmarks for D7 / D30 / D90 | Toggle report period |

**Sync Slicers:** Enable "Sync Slicers" (View → Sync Slicers) for DateTable[Date] across all pages.

---

## Row-Level Security (RLS)

Define these roles in Power BI Desktop → **Modeling → Manage Roles**:

| Role | DAX Filter | Access |
|------|------------|--------|
| `Executive` | No filter (full access) | C-Suite, Senior Leadership |
| `SiteOwner` | `SiteOverview[OwnerPrincipalName] = USERPRINCIPALNAME()` | Site owners see own site only |
| `HRViewer` | No filter on users, no individual UPN visibility | HR team (demographics only) |
| `NoUserPII` | Add `UserDemographics[UPN] = "obfuscated"` or hide UPN column | Default for most users |

Apply RLS in Power BI Service: Dataset → Security → assign Azure AD groups to roles.

---

## Branding / Theme

- **Primary color:** Contoso Corporate Blue `#003087`
- **Accent color:** Contoso Gold `#FFB81C`
- **Background:** Light gray `#F5F5F5`
- **Font:** Segoe UI (Power BI default)
- Import a JSON theme file (place in same folder as the .pbit) for consistent branding.
