
<# 
  07-PostMigration-Flow-Assist-Destination.ps1
  Purpose: Post-migration tasks in TARGET tenant - list flows and optionally enable disabled ones
  Note: Flows will only enable if their connections/connection references are valid
  Important: Run this script in the TARGET tenant after migration completion
#>

param(
  [Parameter(Mandatory=$false)][string]$EnvironmentDisplayName,
  [Parameter(Mandatory=$false)][string]$TargetTenantId,
  [switch]$EnableAllDisabled
)

. .\Config.ps1

# Use config values if parameters not provided
if ([string]::IsNullOrWhiteSpace($EnvironmentDisplayName)) { $EnvironmentDisplayName = $Global:EnvironmentDisplayName }
if ([string]::IsNullOrWhiteSpace($TargetTenantId)) { $TargetTenantId = $Global:TargetTenantId }

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($EnvironmentDisplayName) -or [string]::IsNullOrWhiteSpace($TargetTenantId)) {
    Write-MigrationLog "EnvironmentDisplayName and TargetTenantId are required" "Error"
    throw "Missing required parameters - check Config.ps1 or provide via parameters"
}

Write-MigrationLog "Starting post-migration flow assistance" "Info"
Write-MigrationLog "Target Environment: $EnvironmentDisplayName" "Info"
Write-MigrationLog "Target Tenant ID: $TargetTenantId" "Info"
Write-MigrationLog "Enable Disabled Flows: $EnableAllDisabled" "Info"

try {
    Write-MigrationLog "Connecting to TARGET tenant..." "Info"
    Add-PowerAppsAccount -Endpoint prod -TenantID $TargetTenantId | Out-Null
    Write-MigrationLog "Successfully connected to TARGET tenant" "Success"
} catch {
    Write-MigrationLog "Failed to connect to TARGET tenant: $($_.Exception.Message)" "Error"
    throw
}

try {
    Write-MigrationLog "Resolving environment in TARGET tenant: $EnvironmentDisplayName" "Info"
    $env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq $EnvironmentDisplayName }
    
    if (-not $env) { 
        $availableEnvs = (Get-AdminPowerAppEnvironment | Select-Object -ExpandProperty DisplayName) -join ', '
        throw "Environment '$EnvironmentDisplayName' not found in TARGET tenant. Available: $availableEnvs" 
    }
    
    $ENV_ID = $env.EnvironmentName
    Write-MigrationLog "Environment resolved - ID: $ENV_ID" "Success"
} catch {
    Write-MigrationLog "Environment resolution failed: $($_.Exception.Message)" "Error"
    throw
}

$outDir = $Global:PostMigrationOutputDir
Write-MigrationLog "Output directory: $outDir" "Info"

try {
    Write-MigrationLog "Retrieving flow inventory from migrated environment..." "Info"
    $flows = Get-AdminFlow -EnvironmentName $ENV_ID |
        Select-Object DisplayName, FlowName, Enabled, SolutionId, CreatedBy, LastModifiedTime
    
    $totalFlows = ($flows | Measure-Object).Count
    $enabledFlows = ($flows | Where-Object { $_.Enabled -eq $true } | Measure-Object).Count
    $disabledFlows = $totalFlows - $enabledFlows
    
    Write-MigrationLog "Flow inventory retrieved - Total: $totalFlows, Enabled: $enabledFlows, Disabled: $disabledFlows" "Success"
    
    # Export flow inventory
    $flowsCsvPath = Join-Path $outDir "flows-after-migration.csv"
    $flows | Export-Csv $flowsCsvPath -NoTypeInformation -Encoding UTF8
    Write-MigrationLog "Flow inventory exported: $flowsCsvPath" "Info"
    
} catch {
    Write-MigrationLog "Failed to retrieve flow inventory: $($_.Exception.Message)" "Error"
    throw
}

if ($EnableAllDisabled -and $disabledFlows -gt 0) {
    Write-MigrationLog "Starting bulk flow enablement for $disabledFlows disabled flows" "Info"
    Write-MigrationLog "Note: Flows will only enable if their connections are properly configured" "Warning"
    
    $toEnable = $flows | Where-Object { $_.Enabled -eq $false }
    $enableSuccess = 0
    $enableFailure = 0
    $enableResults = @()
    
    foreach ($f in $toEnable) {
        Write-MigrationLog "Attempting to enable flow: $($f.DisplayName)" "Info"
        
        $result = [pscustomobject]@{
            FlowName = $f.FlowName
            DisplayName = $f.DisplayName
            SolutionId = $f.SolutionId
            AttemptTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Success = $false
            ErrorMessage = ""
        }
        
        try {
            Enable-AdminFlow -EnvironmentName $ENV_ID -FlowName $f.FlowName -ErrorAction Stop
            Write-MigrationLog "Successfully enabled: $($f.DisplayName)" "Success"
            $result.Success = $true
            $enableSuccess++
        } catch {
            $errorMsg = $_.Exception.Message
            Write-MigrationLog "Failed to enable $($f.DisplayName): $errorMsg" "Warning"
            $result.ErrorMessage = $errorMsg
            $enableFailure++
        }
        
        $enableResults += $result
        
        # Brief pause between enable attempts
        Start-Sleep -Seconds 1
    }
    
    Write-MigrationLog "Flow enablement completed - Success: $enableSuccess, Failed: $enableFailure" "Info"
    
    # Export enable results
    $enableResultsPath = Join-Path $outDir "flow-enable-results.csv"
    $enableResults | Export-Csv $enableResultsPath -NoTypeInformation -Encoding UTF8
    Write-MigrationLog "Enable results exported: $enableResultsPath" "Info"
    
    if ($enableFailure -gt 0) {
        Write-MigrationLog "$enableFailure flows could not be enabled - likely due to missing connections" "Warning"
        Write-MigrationLog "Review connection references in the Power Platform admin center" "Warning"
    }
    
} elseif ($EnableAllDisabled -and $disabledFlows -eq 0) {
    Write-MigrationLog "No disabled flows found - all flows are already enabled" "Success"
} else {
    Write-MigrationLog "Flow enablement skipped (use -EnableAllDisabled to enable disabled flows)" "Info"
}

# Generate comprehensive post-migration report
$reportPath = Join-Path $outDir "post-migration-report.txt"
$report = @"
Power Platform Migration - Post-Migration Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Environment: $EnvironmentDisplayName ($ENV_ID)
Target Tenant ID: $TargetTenantId

=== FLOW SUMMARY ===
Total Flows: $totalFlows
Enabled Flows: $enabledFlows
Disabled Flows: $disabledFlows

$(if ($EnableAllDisabled) {
"=== ENABLEMENT RESULTS ===
Enable Attempts: $disabledFlows
Successful: $enableSuccess
Failed: $enableFailure
"
} else {
"=== ENABLEMENT STATUS ===
Bulk enablement: Not performed (use -EnableAllDisabled switch)
"
})
=== CRITICAL POST-MIGRATION TASKS ===
1. Re-authenticate ALL connection references in Power Platform admin center
2. Update any HTTP trigger URLs in external systems
3. Test all critical flows manually
4. Verify custom connector functionality
5. Check SharePoint/Teams integrations
6. Update any hard-coded tenant-specific URLs
7. Validate security permissions and sharing

=== FILES GENERATED ===
- flows-after-migration.csv (complete flow inventory)
$(if ($EnableAllDisabled) { "- flow-enable-results.csv (enablement attempt results)" })
- post-migration-report.txt (this report)

=== NEXT STEPS ===
1. Review all disabled flows and their connection dependencies
2. Manually re-authenticate connection references via admin center
3. Test critical business processes end-to-end
4. Update documentation with new tenant URLs
5. Communicate completion to stakeholders
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-MigrationLog "Post-migration report generated: $reportPath" "Info"

Write-MigrationLog "=== CRITICAL REMINDERS ===" "Warning"
Write-MigrationLog "1. Re-authenticate connection references in Solutions before testing flows" "Warning"
Write-MigrationLog "2. Update HTTP trigger URLs in external systems" "Warning"
Write-MigrationLog "3. Test all critical flows manually" "Warning"
Write-MigrationLog "4. Verify custom connector functionality" "Warning"
Write-MigrationLog "5. Check and update any hard-coded URLs" "Warning"

Write-MigrationLog "🎉 POST-MIGRATION TASKS COMPLETED! 🎉" "Success"
Write-MigrationLog "Migration process is now complete - proceed with testing and validation" "Success"
