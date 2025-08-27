
<#
 Runbook_TTT_AllInOne.ps1
 Purpose: Orchestrated, step-by-step runbook for Power Platform/Dynamics 365 tenant-to-tenant migration.
 Requirements: Windows PowerShell 5.1 (recommended) inside VS Code + PowerShell extension.
 Author: (you) Javi & team

 USAGE (examples):
   # Run interactively with defaults
   .\Runbook_TTT_AllInOne.ps1

   # Provide parameters explicitly
   .\Runbook_TTT_AllInOne.ps1 -EnvironmentDisplayName "CustomerExperienceDev" -TargetTenantId "<GUID_TargetTenant>" `
      -UserMappingCsvPath "C:\migracion\usermapping.csv" -SecurityGroupId "<optional GUID>"
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$EnvironmentDisplayName = "CustomerExperienceDev",
  [string]$TargetTenantId = "<GUID_Tenant_Destino>",
  [string]$UserMappingCsvPath = "C:\migracion\usermapping.csv",
  [string]$SecurityGroupId
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "TTT Runbook - $EnvironmentDisplayName"

# ---------- helpers ----------
function Write-Title($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Step($n, $text) { Write-Host ("`n[{0}] {1}" -f $n, $text) -ForegroundColor Yellow }
function Confirm-Continue([string]$message="Continue? (Y/N)") {
  $ans = Read-Host $message
  if($ans -notin @("Y","y","Yes","YES")){ throw "Canceled by user." }
}
function Ensure-Dir($path){ if(-not (Test-Path $path)){ New-Item -ItemType Directory -Force -Path $path | Out-Null } }

$OUT = Join-Path (Resolve-Path ".\") "runbook-output"
Ensure-Dir $OUT

# ---------- step 0: prerequisites ----------
function Step0_Prereqs {
  Write-Step 0 "Prerequisites check / install"
  try {
    # Policy
    try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force | Out-Null } catch {}
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $mods = @(
      "Microsoft.PowerApps.Administration.PowerShell",
      "Microsoft.PowerApps.PowerShell",
      "Az"
    )
    foreach($m in $mods){
      if(-not (Get-Module -ListAvailable $m)){
        Write-Host "Installing module $m..." -ForegroundColor DarkCyan
        Install-Module $m -Scope CurrentUser -AllowClobber -Force
      }
    }
    Write-Host "Prerequisites OK." -ForegroundColor Green
  } catch {
    Write-Warning "Prereq step failed: $($_.Exception.Message)"
    throw
  }
}

# ---------- step 1: resolve environment in SOURCE ----------
function Step1_ResolveEnv {
  Write-Step 1 "Login SOURCE and resolve EnvironmentName by display name '$EnvironmentDisplayName'"
  Add-PowerAppsAccount -Endpoint prod | Out-Null
  $global:ENV = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq $EnvironmentDisplayName }
  if(-not $ENV){ throw "Environment '$EnvironmentDisplayName' not found in SOURCE." }
  $global:ENV_ID = $ENV.EnvironmentName
  Write-Host "EnvironmentName (SOURCE): $ENV_ID" -ForegroundColor Green
}

# ---------- step 2: inventory (SOURCE) ----------
function Step2_Inventory {
  Write-Step 2 "Inventory SOURCE (flows/apps/connectors)"
  $dir = Join-Path $OUT "inventory"
  Ensure-Dir $dir

  Get-AdminFlow -EnvironmentName $ENV_ID |
    Select-Object DisplayName, Enabled, SolutionId, FlowName, CreatedTime, LastModifiedTime, CreatedBy |
    Export-Csv (Join-Path $dir "flows.csv") -NoTypeInformation -Encoding UTF8

  Get-AdminPowerApp -EnvironmentName $ENV_ID |
    Select-Object DisplayName, AppName, AppType, CreatedTime, LastModifiedTime, Owner |
    Export-Csv (Join-Path $dir "apps.csv") -NoTypeInformation -Encoding UTF8

  try { $connectors = Get-AdminPowerAppConnector -EnvironmentName $ENV_ID -ErrorAction Stop } catch {
    try { $connectors = Get-AdminConnector -EnvironmentName $ENV_ID -ErrorAction Stop } catch { $connectors = $null }
  }
  if($connectors){
    $connectors | Select-Object Name, DisplayName, ConnectorType, CreatedTime, Owner |
      Export-Csv (Join-Path $dir "custom-connectors.csv") -NoTypeInformation -Encoding UTF8
  }
  Write-Host "Inventory exported to $dir" -ForegroundColor Green
  Write-Host "Remember to export & remove Custom Pages/Canvas, and export Custom Connectors before migration." -ForegroundColor Yellow
}

# ---------- step 3: submit (SOURCE) ----------
function Step3_Submit {
  Write-Step 3 "Submit migration request from SOURCE to TARGET TenantId $TargetTenantId"
  TenantToTenant-SubmitMigrationRequest -EnvironmentName $ENV_ID -TargetTenantID $TargetTenantId
  Write-Host "Submitted. Next: approve in TARGET (Step 4)." -ForegroundColor Green
}

# ---------- step 4: approve (TARGET) ----------
function Step4_Approve {
  Write-Step 4 "Login TARGET and approve migration request"
  Add-PowerAppsAccount -Endpoint prod -TenantID $TargetTenantId | Out-Null
  $req = TenantToTenant-ViewMigrationRequest -TenantID $TargetTenantId
  $global:MIGRATION_ID = $req.MigrationId
  if(-not $MIGRATION_ID){ throw "No pending MigrationId found in TARGET. Are you in the right tenant?" }
  TenantToTenant-ManageMigrationRequest -MigrationId $MIGRATION_ID -Approve
  Write-Host "Approved MigrationId: $MIGRATION_ID" -ForegroundColor Green
  ($req | Out-String) | Set-Content (Join-Path $OUT "approval.txt")
}

# ---------- step 5: upload mapping + prepare (SOURCE) ----------
function Step5_Prepare {
  Write-Step 5 "Upload user mapping CSV and run Prepare (SOURCE)"
  if(-not $MIGRATION_ID){ $global:MIGRATION_ID = Read-Host "Enter MigrationId (from Step 4)" }
  if(-not (Test-Path $UserMappingCsvPath)){ throw "UserMapping CSV not found: $UserMappingCsvPath" }

  Add-PowerAppsAccount -Endpoint prod | Out-Null
  TenantToTenant-UploadUserMappingFile -EnvironmentName $ENV_ID -UserMappingFilePath $UserMappingCsvPath
  TenantToTenant-PrepareMigration -MigrationId $MIGRATION_ID -TargetTenantId $TargetTenantId

  $log = Join-Path $OUT "prepare-status.log"
  Write-Host "Polling Prepare status (20s)..." -ForegroundColor DarkCyan
  do {
    Start-Sleep -Seconds 20
    $st = TenantToTenant-GetMigrationStatus -MigrationId $MIGRATION_ID
    ("{0}  Status: {1}  Progress: {2}%" -f (Get-Date), $st.Status, $st.Progress) | Tee-Object -FilePath $log -Append
    Write-Host ("Status: {0}  Progress: {1}%" -f $st.Status, $st.Progress) -ForegroundColor Yellow
  } while ($st.Status -in @("NotStarted","Running","InProgress","Queued"))

  Write-Host "Prepare finished: $($st.Status)" -ForegroundColor Green
  if($st.Status -ne "Succeeded"){ $st | Format-List }
}

# ---------- step 6: migrate (SOURCE) ----------
function Step6_Migrate {
  Write-Step 6 "Execute migration (SOURCE)"
  if(-not $MIGRATION_ID){ $global:MIGRATION_ID = Read-Host "Enter MigrationId" }
  Add-PowerAppsAccount -Endpoint prod | Out-Null

  if([string]::IsNullOrWhiteSpace($SecurityGroupId)){
    TenantToTenant-MigratePowerAppEnvironment -MigrationId $MIGRATION_ID -TargetTenantId $TargetTenantId
  } else {
    TenantToTenant-MigratePowerAppEnvironment -MigrationId $MIGRATION_ID -TargetTenantId $TargetTenantId -SecurityGroupId $SecurityGroupId
  }

  $log = Join-Path $OUT "migration-status.log"
  Write-Host "Polling Migration status (30s)..." -ForegroundColor DarkCyan
  do {
    Start-Sleep -Seconds 30
    $st = TenantToTenant-GetMigrationStatus -MigrationId $MIGRATION_ID
    ("{0}  Status: {1}  Progress: {2}%" -f (Get-Date), $st.Status, $st.Progress) | Tee-Object -FilePath $log -Append
    Write-Host ("Status: {0}  Progress: {1}%" -f $st.Status, $st.Progress) -ForegroundColor Yellow
  } while ($st.Status -in @("NotStarted","Running","InProgress","Queued"))

  Write-Host "Migration finished: $($st.Status)" -ForegroundColor Green
  if($st.Status -ne "Succeeded"){ $st | Format-List }
}

# ---------- step 7: post-migration (TARGET) ----------
function Step7_Post {
  Write-Step 7 "TARGET – list flows (and optionally enable disabled after fixing connections)"
  Add-PowerAppsAccount -Endpoint prod -TenantID $TargetTenantId | Out-Null

  $env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq $EnvironmentDisplayName }
  if(-not $env){ throw "Environment '$EnvironmentDisplayName' not found in TARGET." }
  $ENV_DEST = $env.EnvironmentName

  $dir = Join-Path $OUT "post"
  Ensure-Dir $dir

  $flows = Get-AdminFlow -EnvironmentName $ENV_DEST |
    Select-Object DisplayName, FlowName, Enabled, SolutionId, CreatedBy, LastModifiedTime

  $flows | Export-Csv (Join-Path $dir "flows-after.csv") -NoTypeInformation -Encoding UTF8
  Write-Host "Flows exported to $dir\flows-after.csv" -ForegroundColor Green

  $ans = Read-Host "Attempt to enable all disabled flows now? (Y/N)"
  if($ans -in @("Y","y","Yes","YES")){
    $toEnable = $flows | Where-Object { $_.Enabled -eq $false }
    foreach($f in $toEnable){
      try { Enable-AdminFlow -EnvironmentName $ENV_DEST -FlowName $f.FlowName -ErrorAction Stop
            Write-Host "Enabled: $($f.DisplayName)" -ForegroundColor Green }
      catch { Write-Warning "Could not enable $($f.DisplayName). Fix connection references first." }
    }
  }

  Write-Host "Remember: Re-authenticate connection references in Solutions; import Custom Page/Connector; revalidate CS mailboxes/queues." -ForegroundColor Yellow
}

# ---------- runbook menu ----------
Write-Title "Tenant-to-Tenant Migration Runbook"
Write-Host "EnvironmentDisplayName: $EnvironmentDisplayName"
Write-Host "TargetTenantId:        $TargetTenantId"
Write-Host "UserMappingCsvPath:    $UserMappingCsvPath"
if($SecurityGroupId){ Write-Host "SecurityGroupId:        $SecurityGroupId" }

$menu = @(
  "0) Prereqs install/check",
  "1) Resolve environment (SOURCE)",
  "2) Inventory (SOURCE)",
  "3) Submit request (SOURCE)",
  "4) Approve request (TARGET)",
  "5) Upload mapping + Prepare (SOURCE)",
  "6) Migrate (SOURCE)",
  "7) Post-migration (TARGET)",
  "Q) Quit"
)

do {
  Write-Host ""
  $menu | ForEach-Object { Write-Host $_ }
  $choice = Read-Host "Select step"
  switch ($choice) {
    "0" { Step0_Prereqs }
    "1" { Step1_ResolveEnv }
    "2" { Step1_ResolveEnv; Step2_Inventory }
    "3" { Step1_ResolveEnv; Step3_Submit }
    "4" { Step4_Approve }
    "5" { Step1_ResolveEnv; Step5_Prepare }
    "6" { Step6_Migrate }
    "7" { Step7_Post }
    "Q" { break }
    "q" { break }
    default { Write-Warning "Unknown option" }
  }
} while ($true)

Write-Host "`nRunbook finished." -ForegroundColor Green
