#Requires -Version 5.1
<#
.SYNOPSIS
    Contoso News Online – Azure AD App Registration Setup
    Automates creation of the Azure AD service principal for Power BI analytics.

.DESCRIPTION
    Creates an Azure AD App Registration with the correct API permissions
    needed for the News Online Power BI analytics solution, then outputs
    the credential values to populate Power BI parameters.

.PREREQUISITES
    - Azure PowerShell module:  Install-Module Az -Scope CurrentUser
    - Microsoft Graph module:   Install-Module Microsoft.Graph -Scope CurrentUser
    - Permissions:              Azure AD Global Admin or Application Administrator

.USAGE
    .\AzureAD_Setup.ps1 -TenantName "contoso" -AppName "PowerBI-NewsOnline-Analytics"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $TenantName,

    [Parameter()]
    [string] $AppName = "PowerBI-NewsOnline-Analytics",

    [Parameter()]
    [string] $HubSiteUrl = "https://$TenantName.sharepoint.com/sites/NewsOnline",

    [Parameter()]
    [string] $OutputFile = ".\Config\app_credentials.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── 1. Connect to Microsoft Graph ─────────────────────────────────────────────
Write-Host "`n[1/7] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All",
                         "Directory.Read.All"
$context   = Get-MgContext
$TenantId  = $context.TenantId
Write-Host "      Connected to tenant: $TenantId" -ForegroundColor Green

# ── 2. Create the App Registration ────────────────────────────────────────────
Write-Host "`n[2/7] Creating App Registration '$AppName'..." -ForegroundColor Cyan

$existingApp = Get-MgApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue
if ($existingApp) {
    Write-Warning "App '$AppName' already exists (Id: $($existingApp.Id)). Using existing app."
    $app = $existingApp
} else {
    $app = New-MgApplication -DisplayName $AppName `
                              -SignInAudience "AzureADMyOrg" `
                              -Notes "Created by PowerBI NewsOnline Analytics setup script"
    Write-Host "      Created: $($app.AppId)" -ForegroundColor Green
}

# ── 3. Create a Client Secret ─────────────────────────────────────────────────
Write-Host "`n[3/7] Creating client secret (valid 2 years)..." -ForegroundColor Cyan
$secretParams = @{
    PasswordCredential = @{
        DisplayName = "PowerBI-Auto-$((Get-Date).ToString('yyyyMMdd'))"
        EndDateTime = (Get-Date).AddYears(2)
    }
}
$secret = Add-MgApplicationPassword -ApplicationId $app.Id @secretParams
$ClientSecret = $secret.SecretText
Write-Host "      Secret created. SAVE THIS VALUE – it will not be shown again." -ForegroundColor Yellow

# ── 4. Create Service Principal ───────────────────────────────────────────────
Write-Host "`n[4/7] Creating Service Principal..." -ForegroundColor Cyan
$sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
if (-not $sp) {
    $sp = New-MgServicePrincipal -AppId $app.AppId
    Write-Host "      Service Principal created: $($sp.Id)" -ForegroundColor Green
} else {
    Write-Host "      Service Principal exists: $($sp.Id)" -ForegroundColor Yellow
}

# ── 5. Assign Microsoft Graph API permissions ──────────────────────────────────
Write-Host "`n[5/7] Assigning Microsoft Graph API permissions..." -ForegroundColor Cyan

$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Required Graph app roles (application permissions)
$graphPermissions = @(
    "Reports.Read.All",        # For usage reports
    "Sites.Read.All",          # For site analytics
    "User.Read.All",           # For user demographics
    "Directory.Read.All"       # For group/org data
)

foreach ($permName in $graphPermissions) {
    $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $permName }
    if ($role) {
        $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id `
                    | Where-Object { $_.AppRoleId -eq $role.Id -and $_.ResourceId -eq $graphSp.Id }
        if (-not $existing) {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId  $sp.Id `
                -PrincipalId         $sp.Id `
                -ResourceId          $graphSp.Id `
                -AppRoleId           $role.Id | Out-Null
            Write-Host "      ✓ Graph: $permName" -ForegroundColor Green
        } else {
            Write-Host "      ○ Graph: $permName (already assigned)" -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Permission '$permName' not found on Microsoft Graph SP."
    }
}

# ── 6. Assign SharePoint API permissions ──────────────────────────────────────
Write-Host "`n[6/7] Assigning SharePoint API permissions..." -ForegroundColor Cyan

$spApiSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0ff1-ce00-000000000000'"

$spPermissions = @("Sites.Read.All")
foreach ($permName in $spPermissions) {
    $role = $spApiSp.AppRoles | Where-Object { $_.Value -eq $permName }
    if ($role) {
        $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id `
                    | Where-Object { $_.AppRoleId -eq $role.Id -and $_.ResourceId -eq $spApiSp.Id }
        if (-not $existing) {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId  $sp.Id `
                -PrincipalId         $sp.Id `
                -ResourceId          $spApiSp.Id `
                -AppRoleId           $role.Id | Out-Null
            Write-Host "      ✓ SharePoint: $permName" -ForegroundColor Green
        } else {
            Write-Host "      ○ SharePoint: $permName (already assigned)" -ForegroundColor Yellow
        }
    }
}

# ── 7. Output credentials ──────────────────────────────────────────────────────
Write-Host "`n[7/7] Writing credentials to output file..." -ForegroundColor Cyan

$outputDir = Split-Path $OutputFile -Parent
if (-not (Test-Path $outputDir)) { New-Item $outputDir -ItemType Directory | Out-Null }

# NOTE: In production, use Azure Key Vault instead of a local JSON file.
# This file should NEVER be committed to source control.
$credentials = [PSCustomObject]@{
    TenantId        = $TenantId
    TenantName      = $TenantName
    ClientId        = $app.AppId
    ClientSecret    = $ClientSecret   # Rotate annually; store in Key Vault for production
    HubSiteUrl      = $HubSiteUrl
    AppName         = $AppName
    ServicePrincipalObjectId = $sp.Id
    CreatedAt       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    ExpiresAt       = (Get-Date).AddYears(2).ToString("yyyy-MM-ddTHH:mm:ssZ")
    Notes           = "Use ClientId and ClientSecret in Power BI gateway/dataset settings. DO NOT SHARE."
}

$credentials | ConvertTo-Json -Depth 3 | Set-Content -Path $OutputFile -Encoding UTF8

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Tenant ID:   $TenantId"
Write-Host "  Client ID:   $($app.AppId)"
Write-Host "  Credentials: $OutputFile"
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Open Azure Portal → App Registrations → $AppName"
Write-Host "  2. Under 'API Permissions', click 'Grant admin consent'"
Write-Host "  3. Open Power BI Desktop and set these parameters:"
Write-Host "     TenantId  = $TenantId"
Write-Host "     ClientId  = $($app.AppId)"
Write-Host "  4. In Power Query data source credentials, use:"
Write-Host "     Authentication: Basic (for service principal)"
Write-Host "     Username: $($app.AppId)"
Write-Host "     Password: [ClientSecret from $OutputFile]"
Write-Host ""
Write-Host "  IMPORTANT: Run 'Grant admin consent' in Azure Portal before" -ForegroundColor Red
Write-Host "  attempting data refresh in Power BI." -ForegroundColor Red
Write-Host ""

# Disconnect cleanly
Disconnect-MgGraph | Out-Null
