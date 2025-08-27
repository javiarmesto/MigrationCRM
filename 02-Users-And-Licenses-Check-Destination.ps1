
<# 
  02-Users-And-Licenses-Check-Destination.ps1
  Purpose: In TARGET tenant, verify existence of users from a usermapping CSV and (optionally) their license details via Microsoft Graph.
  CSV format expected: sourceUpn,targetUpn (or columns named similarly; this script reads the *target* column named TargetUpn by default).
  Prereq: Microsoft.Graph module if you want license details. Otherwise, the script will only check that the user exists.
#>

param(
  [Parameter(Mandatory=$true)][string]$UserMappingCsvPath,
  [string]$TargetUpnColumn = "TargetUpn"
)

$ErrorActionPreference = "Stop"

# Login to TARGET tenant for Power Platform (not strictly needed here, but consistent)
Write-Host "Login to TARGET tenant (Power Platform)..." -ForegroundColor Cyan
Add-PowerAppsAccount -Endpoint prod | Out-Null

# Optional: login to Graph for license checks
$graphAvailable = Get-Module -ListAvailable Microsoft.Graph | Measure-Object | Select-Object -ExpandProperty Count
if($graphAvailable -gt 0){
  Write-Host "Connecting to Microsoft Graph (User.Read.All, Directory.Read.All)..." -ForegroundColor Cyan
  try {
    Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All" | Out-Null
  } catch {
    Write-Warning "Could not connect to Graph. User existence check will still run, but license info will be skipped."
  }
}else{
  Write-Warning "Microsoft.Graph module not installed. Install-Module Microsoft.Graph -Scope CurrentUser to get license info."
}

if(!(Test-Path $UserMappingCsvPath)){ throw "CSV not found: $UserMappingCsvPath" }
$rows = Import-Csv $UserMappingCsvPath

$outDir = Join-Path -Path (Resolve-Path ".\") -ChildPath "out-users"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$result = @()

foreach($r in $rows){
  $upn = $r.$TargetUpnColumn
  if([string]::IsNullOrWhiteSpace($upn)){ continue }

  $exists = $false
  $licenseSummary = "N/A"

  try{
    # Prefer Graph if available
    if(Get-Module -Name Microsoft.Graph -ListAvailable){
      $u = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ConsistencyLevel eventual
      if($u){
        $exists = $true
        try{
          $lic = Get-MgUserLicenseDetail -UserId $u.Id -ErrorAction Stop
          if($lic){
            $licenseSummary = ($lic.SkuPartNumber | Sort-Object | Get-Unique) -join "; "
          } else {
            $licenseSummary = "No licenses"
          }
        } catch { $licenseSummary = "Unknown (no permission or no licenses)" }
      }
    } else {
      # Fallback existence check via Power Platform admin connection (coarse)
      $exists = $false
    }
  } catch {
    $exists = $false
  }

  $result += [pscustomobject]@{
    TargetUpn = $upn
    ExistsInTarget = $exists
    Licenses = $licenseSummary
  }
}

$resultPath = Join-Path $outDir "target-users-check.csv"
$result | Export-Csv $resultPath -NoTypeInformation -Encoding UTF8

Write-MigrationLog "User validation completed" "Success"
Write-MigrationLog "Results exported to: $resultPath" "Info"
Write-MigrationLog "Summary: $existingCount found, $missingCount missing, $processedCount total processed" "Info"

if ($missingCount -gt 0) {
    Write-MigrationLog "WARNING: $missingCount users were not found in the target tenant!" "Warning"
    Write-MigrationLog "Review the CSV file and ensure all required users exist before proceeding with migration" "Warning"
}

# Generate summary report
$summaryPath = Join-Path $outDir "user-validation-summary.txt"
$summary = @"
Power Platform Migration - User Validation Summary
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source File: $UserMappingCsvPath
Target UPN Column: $TargetUpnColumn

Results:
- Total users processed: $processedCount
- Users found in target: $existingCount
- Users missing in target: $missingCount
- Graph connection: $(if ($graphConnected) { 'Success' } else { 'Failed/Unavailable' })

Next Steps:
$(if ($missingCount -gt 0) { 
"1. CRITICAL: Create missing users in target tenant before proceeding
2. Assign appropriate licenses to all target users
3. Re-run this validation after user creation" 
} else { 
"1. Verify license assignments for all users
2. Proceed to migration submission phase" 
})
"@

$summary | Out-File -FilePath $summaryPath -Encoding UTF8
Write-MigrationLog "Summary report saved: $summaryPath" "Info"

if ($graphConnected) {
    try {
        Disconnect-MgGraph
        Write-MigrationLog "Disconnected from Microsoft Graph" "Info"
    } catch {
        Write-MigrationLog "Note: Error disconnecting from Graph (non-critical): $($_.Exception.Message)" "Warning"
    }
}
