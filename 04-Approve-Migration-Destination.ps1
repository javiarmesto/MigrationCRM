
<# 
  04-Approve-Migration-Destination.ps1
  Purpose: Approve migration request in TARGET tenant.
#>

param(
  [Parameter(Mandatory=$true)][string]$TargetTenantId
)

Add-PowerAppsAccount -Endpoint prod -TenantID $TargetTenantId | Out-Null

Write-Host "Pending requests in TARGET:" -ForegroundColor Cyan
$req = TenantToTenant-ViewMigrationRequest -TenantID $TargetTenantId
$req | Format-List

$MigrationId = $req.MigrationId
if(-not $MigrationId){ throw "No pending MigrationId found. Are you in the right tenant?" }
TenantToTenant-ManageMigrationRequest -MigrationId $MigrationId -Approve
Write-MigrationLog "Migration request approved successfully!" "Success"
Write-MigrationLog "Migration ID: $MigrationId" "Success"

Write-MigrationLog "=== IMPORTANT: SAVE THE MIGRATION ID ===" "Warning"
Write-MigrationLog "Migration ID: $MigrationId" "Warning"
Write-MigrationLog "1. Update Config.ps1 with this MigrationId" "Warning"
Write-MigrationLog "2. This ID is required for all subsequent migration steps" "Warning"
Write-MigrationLog "3. Proceed to user mapping and preparation phase" "Warning"

# Save approval details for reference
$approvalPath = Join-Path $Global:OutputDirectory "migration-approval.txt"
$approvalDetails = @"
Power Platform Migration - Approval Details
Approved: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Target Tenant ID: $TargetTenantId
Migration ID: $MigrationId

Status: APPROVED - Ready for preparation phase

Next Steps:
1. CRITICAL: Update Config.ps1 with MigrationId: $MigrationId
2. Prepare user mapping CSV file
3. Run 05-UploadMapping-Prepare-Origin.ps1 from SOURCE tenant

Migration Request Details:
$($req | Out-String)
"@

$approvalDetails | Out-File -FilePath $approvalPath -Encoding UTF8
Write-MigrationLog "Approval details saved: $approvalPath" "Info"

# Auto-update Config.ps1 if possible
try {
    $configPath = ".\Config.ps1"
    if (Test-Path $configPath) {
        $configContent = Get-Content $configPath -Raw
        if ($configContent -match '\$Global:MigrationId = ""') {
            $updatedConfig = $configContent -replace '\$Global:MigrationId = ""', "`$Global:MigrationId = `"$MigrationId`""
            Set-Content $configPath -Value $updatedConfig -Encoding UTF8
            Write-MigrationLog "Config.ps1 automatically updated with MigrationId" "Success"
        }
    }
} catch {
    Write-MigrationLog "Could not auto-update Config.ps1: $($_.Exception.Message)" "Warning"
    Write-MigrationLog "Please manually update Config.ps1 with MigrationId: $MigrationId" "Warning"
}

Write-MigrationLog "Migration approval process completed" "Success"
