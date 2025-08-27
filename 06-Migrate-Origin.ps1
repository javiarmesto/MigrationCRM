
<# 
  06-Migrate-Origin.ps1
  Purpose: Execute the migration in SOURCE tenant and poll until completion
  Note: This is the actual migration execution - ensure all preparation is complete
#>

param(
  [Parameter(Mandatory=$false)][string]$MigrationId,
  [Parameter(Mandatory=$false)][string]$TargetTenantId,
  [Parameter(Mandatory=$false)][string]$SecurityGroupId
)

. .\Config.ps1

# Use config values if parameters not provided
if ([string]::IsNullOrWhiteSpace($MigrationId)) { $MigrationId = $Global:MigrationId }
if ([string]::IsNullOrWhiteSpace($TargetTenantId)) { $TargetTenantId = $Global:TargetTenantId }
if ([string]::IsNullOrWhiteSpace($SecurityGroupId)) { $SecurityGroupId = $Global:SecurityGroupId }

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($MigrationId) -or [string]::IsNullOrWhiteSpace($TargetTenantId)) {
    Write-MigrationLog "MigrationId and TargetTenantId are required" "Error"
    throw "Missing required parameters - check Config.ps1 or provide via parameters"
}

Write-MigrationLog "Starting migration execution" "Info"
Write-MigrationLog "Migration ID: $MigrationId" "Info"
Write-MigrationLog "Target Tenant ID: $TargetTenantId" "Info"
if (![string]::IsNullOrWhiteSpace($SecurityGroupId)) {
    Write-MigrationLog "Security Group ID: $SecurityGroupId" "Info"
}

try {
    Write-MigrationLog "Connecting to SOURCE tenant..." "Info"
    Add-PowerAppsAccount -Endpoint prod | Out-Null
    Write-MigrationLog "Successfully connected to SOURCE tenant" "Success"
} catch {
    Write-MigrationLog "Failed to connect to SOURCE tenant: $($_.Exception.Message)" "Error"
    throw
}

Write-MigrationLog "=== CRITICAL: STARTING ACTUAL MIGRATION ===" "Warning"
Write-MigrationLog "This will begin the irreversible migration process" "Warning"
Write-MigrationLog "Ensure all preparation steps are complete" "Warning"

try {
    Write-MigrationLog "Executing migration command..." "Info"
    
    if (![string]::IsNullOrWhiteSpace($SecurityGroupId)) {
        Write-MigrationLog "Including Security Group ID in migration" "Info"
        TenantToTenant-MigratePowerAppEnvironment -MigrationId $MigrationId -TargetTenantId $TargetTenantId -SecurityGroupId $SecurityGroupId
    } else {
        TenantToTenant-MigratePowerAppEnvironment -MigrationId $MigrationId -TargetTenantId $TargetTenantId
    }
    
    Write-MigrationLog "Migration command executed successfully" "Success"
} catch {
    Write-MigrationLog "Failed to execute migration: $($_.Exception.Message)" "Error"
    throw
}

Write-MigrationLog "Monitoring migration progress (polling every $($Global:MigrationPollingInterval)s)..." "Info"
Write-MigrationLog "Migration can take several hours depending on environment size" "Info"

$startTime = Get-Date
$maxWaitHours = 12 # Maximum wait time for large migrations
$lastProgress = -1
$stuckCount = 0

do {
    Start-Sleep -Seconds $Global:MigrationPollingInterval
    
    try {
        $st = TenantToTenant-GetMigrationStatus -MigrationId $MigrationId
        $status = $st.Status
        $progress = $st.Progress
        
        $elapsed = New-TimeSpan -Start $startTime
        $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed
        
        Write-MigrationLog "Status: $status | Progress: $progress% | Elapsed: $elapsedStr" "Info"
        
        # Check for stuck progress
        if ($progress -eq $lastProgress -and $status -in @("Running", "InProgress")) {
            $stuckCount++
            if ($stuckCount -ge 10) { # 10 consecutive same progress updates
                Write-MigrationLog "Progress appears stuck at $progress% for $($stuckCount * $Global:MigrationPollingInterval) seconds" "Warning"
                $stuckCount = 0 # Reset counter
            }
        } else {
            $stuckCount = 0
        }
        $lastProgress = $progress
        
        # Check for timeout
        if ($elapsed.TotalHours -gt $maxWaitHours) {
            Write-MigrationLog "Migration has exceeded maximum wait time of $maxWaitHours hours" "Warning"
            Write-MigrationLog "Current status: $status ($progress%)" "Warning"
            
            $continue = Read-Host "Continue waiting? (Y/N) [Default: Y]"
            if ($continue -eq "N" -or $continue -eq "n") {
                throw "Migration monitoring terminated by user after $($elapsed.TotalHours) hours"
            }
            $maxWaitHours += 4 # Extend timeout by 4 hours
        }
        
    } catch {
        Write-MigrationLog "Error getting migration status: $($_.Exception.Message)" "Error"
        
        # For status check errors, wait longer before retry
        Write-MigrationLog "Waiting 2 minutes before retry..." "Warning"
        Start-Sleep -Seconds 120
        continue
    }
    
} while ($status -in @("NotStarted", "Running", "InProgress", "Queued"))

$totalTime = New-TimeSpan -Start $startTime
$totalTimeStr = "{0:hh\:mm\:ss}" -f $totalTime
Write-MigrationLog "Migration completed after $totalTimeStr" "Info"
Write-MigrationLog "Final status: $status" $(if ($status -eq "Succeeded") { "Success" } else { "Error" })

if ($status -eq "Succeeded") {
    Write-MigrationLog "🎉 MIGRATION COMPLETED SUCCESSFULLY! 🎉" "Success"
    Write-MigrationLog "Environment has been migrated to target tenant" "Success"
    Write-MigrationLog "Total migration time: $totalTimeStr" "Success"
} else {
    Write-MigrationLog "❌ MIGRATION FAILED - Status: $status" "Error"
    Write-MigrationLog "Detailed status information:" "Error"
    $st | Format-List | Out-String | Write-MigrationLog -Level "Error"
    
    # Save error details for analysis
    $errorPath = Join-Path $Global:OutputDirectory "migration-error-details.txt"
    $errorDetails = @"
Power Platform Migration - Migration Error Details
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Migration ID: $MigrationId
Final Status: $status
Total Time: $totalTimeStr

Detailed Status Object:
$($st | Out-String)
"@
    
    $errorDetails | Out-File -FilePath $errorPath -Encoding UTF8
    Write-MigrationLog "Error details saved: $errorPath" "Info"
    
    throw "Migration failed with status: $status"
}

# Save successful migration details
$migrationPath = Join-Path $Global:OutputDirectory "migration-success.txt"
$migrationDetails = @"
Power Platform Migration - Migration Success
Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Migration ID: $MigrationId
Target Tenant ID: $TargetTenantId
Total Time: $totalTimeStr
$(if (![string]::IsNullOrWhiteSpace($SecurityGroupId)) { "Security Group ID: $SecurityGroupId" })

Status: COMPLETED - Environment successfully migrated

Next Steps:
1. Run 07-PostMigration-Flow-Assist-Destination.ps1 in TARGET tenant
2. Re-authenticate connection references
3. Enable and test migrated flows
4. Validate all migrated components

Final Status Object:
$($st | Out-String)
"@

$migrationDetails | Out-File -FilePath $migrationPath -Encoding UTF8
Write-MigrationLog "Migration details saved: $migrationPath" "Info"

Write-MigrationLog "=== NEXT STEPS ===" "Warning"
Write-MigrationLog "1. Run post-migration tasks via 07-PostMigration-Flow-Assist-Destination.ps1" "Warning"
Write-MigrationLog "2. Re-authenticate all connection references in TARGET tenant" "Warning"
Write-MigrationLog "3. Test and validate migrated components" "Warning"
Write-MigrationLog "4. Enable flows and update any hard-coded URLs" "Warning"
