# Contoso News Online – SharePoint Analytics Power BI Solution

## Overview
This solution delivers a fully parameterized Power BI template (`.pbit`) for Contoso's **News Online** intranet SharePoint Hub-and-Spoke collection. It tracks site usage, page/document engagement, user demographics, content metadata, and social reactions across the entire tenant.

## Dashboard Mockup
<img width="1794" height="905" alt="Screenshot_22-5-2026_122440_" src="https://github.com/user-attachments/assets/52d981a6-eccc-44ee-88f0-f97997ecb046" />

---

## Report Pages

| Page | Description |
|------|-------------|
| **1 – Executive Summary** | KPIs across all News Online sites: total views, active users, top sites, trend sparklines |
| **2 – Site Overview** | All hub + spoke sites: page views, unique visitors, active file count, storage |
| **3 – Hub & Spoke Breakdown** | Drill from hub → spoke → page, with site-level comparison |
| **4 – Page & Document Analytics** | Top pages, top documents, view trends, time-on-page proxy |
| **5 – Content Metadata / Keywords** | Views and engagement by custom metadata tags, topics, and content types |
| **6 – User Demographics** | Activity by department, job title, city, and country |
| **7 – Engagement (Likes & Shares)** | Like counts, reaction trends, sharing activity per page/document |
| **8 – Custom Date Range Slicer** | Cross-page slicer for ad hoc date filtering |

---

## Prerequisites

### 1 – Azure AD App Registration
Run `Setup\AzureAD_Setup.ps1` (see below) or follow these manual steps:

1. Go to **Azure Portal → Azure Active Directory → App Registrations → New Registration**
2. Name: `PowerBI-NewsOnline-Analytics`
3. Supported account types: **Single tenant**
4. Note the **Application (client) ID** and **Tenant ID**
5. Under **Certificates & Secrets → New Client Secret** – copy the value immediately
6. Under **API Permissions → Add a permission**:

| API | Permission | Type |
|-----|-----------|------|
| Microsoft Graph | `Reports.Read.All` | Application |
| Microsoft Graph | `Sites.Read.All` | Application |
| Microsoft Graph | `User.Read.All` | Application |
| Microsoft Graph | `Directory.Read.All` | Application |
| SharePoint | `Sites.Read.All` | Application |

7. Click **Grant admin consent**
admin
### 2 – SharePoint Requirements
- The News Online Hub site URL (e.g., `https://contoso.sharepoint.com/sites/NewsOnline`)
- Site Collection Admin access to hub + all spokes
- Modern SharePoint pages (classic pages have limited analytics support)
- Ensure **Site Analytics** is enabled (Site Settings → Site Analytics)

### 3 – Power BI Requirements
- Power BI Desktop (latest version)
- Power BI Pro or Premium license for scheduled refresh
- Network access to Microsoft Graph and SharePoint endpoints

---

## Setup Instructions

### Step 1 – Configure Parameters
Edit `Config\parameters_template.json` with your tenant values, then reference these when setting Power BI parameters:

| Parameter Name | Example Value | Description |
|----------------|---------------|-------------|
| `TenantId` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | Azure AD Tenant ID |
| `TenantName` | `contoso` | Tenant name (the part before `.onmicrosoft.com`) |
| `HubSiteUrl` | `https://contoso.sharepoint.com/sites/NewsOnline` | Hub site root URL |
| `ReportPeriod` | `D30` | Graph API period: D7, D30, D90, or D180 |
| `ClientId` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | App Registration Client ID |
| `SpokeUrls` | (list – see 05_KeywordMetadata.pq) | Comma-separated spoke site URLs |

### Step 2 – Import Power Query Files
For each `.pq` file in `PowerQuery\`:
1. Open Power BI Desktop
2. **Home → Transform Data → Power Query Editor**
3. **New Source → Blank Query**
4. Open **Advanced Editor** and paste the contents of each `.pq` file
5. Rename the query to the table name the DAX measures expect — **drop the number prefix**:

| File | Query name to use |
|------|-------------------|
| `02_SiteOverview.pq` | `SiteOverview` |
| `03_HubSpokeAnalytics.pq` | `HubSpokeAnalytics` |
| `04_PageDocAnalytics.pq` | `PageDocAnalytics` |
| `05_KeywordMetadata.pq` | `KeywordMetadata` |
| `06_UserDemographics.pq` | `UserDemographics` |
| `07_EngagementAnalytics.pq` | `EngagementAnalytics` |
| `08_DateTable.pq` | `DateTable` |

> The number prefixes are just for file ordering — they must not be included in the query/table name or the DAX measures will fail to find the tables.

### Step 3 – Import DAX Measures

`DAX\All_Measures.dax` contains 7 sections of measures. All measures are written into a dedicated `_Measures` table.

#### 3a – Create the Measures Table

1. In Power BI Desktop, click the **Modeling** tab in the ribbon
2. Click **New Table**
3. Enter the following in the formula bar and press **Enter**:
   ```
   _Measures = ROW("_", BLANK())
   ```

> `Measures` is a reserved word in Power BI — use `_Measures` instead.

#### 3b – Import Measures via DAX Query View

1. Click the **DAX Query View** icon in the left navigation bar (below Model view)
2. Paste the full contents of `DAX\All_Measures.dax` into the editor
3. Click **Run** — the Results pane should show `Value: 1`
4. Click **Update model with changes** — Power BI will prompt *"Are you sure?"* — click **Update model** to confirm

All measures are now written to the `_Measures` table.

#### 3c – Post-Import: Mark DateTable as a Date Table

The time-intelligence measures (YTD, MoM, rolling windows) require `DateTable` to be marked as a date table:

1. In **Modeling view**, select the `DateTable` table
2. **Table tools → Mark as date table**
3. Set the date column to `DateTable[Date]`

#### 3d – Verify

In the **Data pane**, expand `_Measures` and confirm all measures are present. Spot-check a few by dragging them onto a blank report page as **Card** visuals to confirm they return values rather than errors.

### Step 4 – Set Up Relationships

#### 4a – Open Model View
Click the **Model view** icon in the left navigation bar (looks like three connected boxes). Each loaded table appears as a card showing its columns.

#### 4b – How to Create a Relationship
**Drag-and-drop method (fastest):**
1. In Model view, find the column in the "many" table (the one with duplicate values)
2. Click and drag it onto the matching column in the "one" table
3. Power BI will auto-detect cardinality — verify it shows **Many to one (*:1)** in the confirmation dialog
4. Click **OK**

**Manage Relationships dialog (more control):**
1. Click **Modeling → Manage relationships** in the ribbon
2. Click **New…** for each relationship
3. Set the From table/column, To table/column, cardinality, and cross-filter direction
4. Click **OK**, then **Close** when all are created

#### 4c – Required Relationships

| From Table (many side) | From Column | To Table (one side) | To Column | Cardinality | Cross-filter |
|------------------------|-------------|---------------------|-----------|-------------|--------------|
| `PageDocAnalytics` | `SiteId` | `SiteOverview` | `SiteId` | Many to one (*:1) | Single |
| `HubSpokeAnalytics` | `SiteId` | `SiteOverview` | `SiteId` | Many to one (*:1) | Single |
| `EngagementAnalytics` | `SiteUrl` | `SiteOverview` | `SiteUrl` | Many to one (*:1) | Single |
| `SiteOverview` | `ReportRefreshDate` | `DateTable` | `Date` | Many to one (*:1) | Single |
| `UserDemographics` | `LastActivityDate` | `DateTable` | `Date` | Many to one (*:1) | Single |

> **Why these relationships?**
> - `PageDocAnalytics` and `HubSpokeAnalytics` join to `SiteOverview` on `SiteId` — this lets site-level slicers (site name, site type) filter page and spoke analytics.
> - `EngagementAnalytics` joins via `SiteUrl` because it has no `SiteId` column — dragging `SiteUrl` from `EngagementAnalytics` onto `SiteUrl` in `SiteOverview` creates the site filter chain.
> - `SiteOverview` and `UserDemographics` connect to `DateTable` — this activates the `_TrendKPIs` time-intelligence measures (YTD, MoM, rolling windows).

> **KeywordMetadata** is a self-contained search fact table. It has no `SiteId` shared with other tables, so it has **no relationships** — leave it unconnected. Filter it in visuals using its own columns: `SearchKeyword`, `ContentType`, `SiteName`.

> **Ambiguous path warning**: `HubSpokeAnalytics` contains both `SiteId` and `SiteUrl` columns. Power BI may auto-detect a relationship between `HubSpokeAnalytics[SiteUrl]` and `EngagementAnalytics[SiteUrl]`, creating two filter paths to `SiteOverview`. If you see an *"ambiguous paths"* error when creating the `HubSpokeAnalytics → SiteOverview` relationship, go to **Modeling → Manage relationships**, delete any auto-detected relationship between `HubSpokeAnalytics` and `EngagementAnalytics`, then retry.

#### 4d – Optional: Enable Date Filtering on Engagement Data

The `Likes 30D Rolling` measure filters via `DateTable[IsLast30Days]`. Without a date relationship on `EngagementAnalytics`, that filter has no effect (the measure will return all-time likes regardless of date context). To fix this:

1. In Power Query Editor, select the **`EngagementAnalytics`** query
2. Go to **Add Column → Custom Column**
   - Name: `ActivityDate`
   - Formula: `DateTime.Date([LastModifiedDate])`
3. Change the new column's type to **Date** (click the column header type icon)
4. Click **Close & Apply**
5. In Model view, drag `EngagementAnalytics[ActivityDate]` onto `DateTable[Date]` to create the relationship (Many to one, Single cross-filter)

#### 4e – Verify the Model

After creating all relationships, your Model view should look like a **star schema**:

```
          DateTable (date dimension)
               │           │
    SiteOverview ◄──── UserDemographics
    (site dimension)
    ▲       ▲       ▲
    │       │       │
PageDoc  HubSpoke  Engagement
Analytics Analytics Analytics

KeywordMetadata  ← isolated (no relationship lines)
_Measures        ← isolated (measure table, no relationships needed)
```

Confirm by clicking each relationship line in Model view — the connecting columns should highlight and show **Many to one (*:1)** in the properties panel.

### Step 5 – Set Credentials
In Power Query Editor:
- For **Microsoft Graph** queries: use **Organizational Account** and sign in with your M365 admin account, OR configure Service Principal via **Basic** credentials (Client ID / Secret) if using app-only auth

### Step 6 – Export as .pbit Template
1. In Power BI Desktop: **File → Export → Power BI Template**
2. Description: `Contoso News Online – SharePoint Analytics v1.0`
3. Save as `Contoso_NewsOnline_Analytics.pbit`

> **Template behavior**: When opened, `.pbit` prompts users to enter parameter values (tenant URL, period, etc.) before loading data. No data is stored in the template file.

---

## Data Refresh
- **Direct Query**: Not supported for Graph API reports (must use Import mode)
- **Scheduled Refresh**: Publish to Power BI Service → Dataset Settings → Scheduled Refresh
- Recommended refresh: **Daily at 6:00 AM** (Graph API data typically has 24–48 hour latency)
- For near-real-time: combine with **SharePoint REST analytics** queries (queries 03–07) which have lower latency

---

## Data Sources Summary

| Query | Endpoint | Auth | Latency |
|-------|----------|------|---------|
| SiteOverview | Graph `/reports/getSharePointSiteUsageDetail` | OAuth/App | 24–48 hrs |
| HubSpokeAnalytics | Graph `/sites/{id}/analytics` | OAuth/App | ~1 hr |
| PageDocAnalytics | Graph `/sites/{id}/drive/items/{id}/analytics` | OAuth/App | ~1 hr |
| KeywordMetadata | SharePoint `/_api/search/postquery` | OAuth | Real-time |
| UserDemographics | Graph `/users` + `/reports/getSharePointActivityUserDetail` | OAuth/App | 24–48 hrs |
| EngagementAnalytics | SharePoint `/_api/sitepages/pages` + reactions | OAuth | ~1 hr |
| DateTable | Calculated (no external source) | N/A | N/A |

---

## Troubleshooting

| Issue | Resolution |
|-------|-----------|
| `403 Forbidden` on Graph API | Verify app permissions granted admin consent |
| `DataSource.Error` on Web.Contents | Check credentials set correctly in Power Query |
| Empty tables | Verify site URLs are correct; check user has site analytics access |
| Missing likes/reactions | Requires Modern SharePoint pages with reactions enabled |
| SharePoint search returns no results | Ensure managed properties are crawled and indexed |
