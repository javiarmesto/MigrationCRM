
<# 
  05-UploadMapping-Prepare-Origin.ps1
  Purpose: Upload user-mapping CSV and run Prepare in SOURCE tenant. Poll status until completion.
  Note: This step must be completed within 7 days of approval per Microsoft documentation
#>

param(
  [Parameter(Mandatory=$false)][string]$EnvironmentDisplayName,
  [Parameter(Mandatory=$false)][string]$MigrationId,
  [Parameter(Mandatory=$false)][string]$TargetTenantId,
  [Parameter(Mandatory=$false)][string]$UserMappingCsvPath
)

. .\Config.ps1

# Use config values if parameters not provided
if ([string]::IsNullOrWhiteSpace($EnvironmentDisplayName)) { $EnvironmentDisplayName = $Global:EnvironmentDisplayName }
if ([string]::IsNullOrWhiteSpace($MigrationId)) { $MigrationId = $Global:MigrationId }
if ([string]::IsNullOrWhiteSpace($TargetTenantId)) { $TargetTenantId = $Global:TargetTenantId }
if ([string]::IsNullOrWhiteSpace($UserMappingCsvPath)) { $UserMappingCsvPath = $Global:UserMappingCsvPath }

# Validate all required parameters
$requiredParams = @{
    "EnvironmentDisplayName" = $EnvironmentDisplayName
    "MigrationId" = $MigrationId
    "TargetTenantId" = $TargetTenantId
    "UserMappingCsvPath" = $UserMappingCsvPath
}

$missingParams = $requiredParams.GetEnumerator() | Where-Object { [string]::IsNullOrWhiteSpace($_.Value) }
if ($missingParams) {
    $missingList = ($missingParams | Select-Object -ExpandProperty Name) -join ', '
    Write-MigrationLog "Missing required parameters: $missingList" "Error"
    throw "Missing required parameters. Update Config.ps1 or provide via parameters."
}

Write-MigrationLog "Starting user mapping upload and preparation phase" "Info"
Write-MigrationLog "Environment: $EnvironmentDisplayName" "Info"
Write-MigrationLog "Migration ID: $MigrationId" "Info"
Write-MigrationLog "Target Tenant: $TargetTenantId" "Info"
Write-MigrationLog "User Mapping CSV: $UserMappingCsvPath" "Info"

try {
    Write-MigrationLog "Connecting to SOURCE tenant..." "Info"
    Add-PowerAppsAccount -Endpoint prod | Out-Null
    Write-MigrationLog "Successfully connected to SOURCE tenant" "Success"
} catch {
    Write-MigrationLog "Failed to connect to SOURCE tenant: $($_.Exception.Message)" "Error"
    throw
}

try {
    Write-MigrationLog "Resolving environment: $EnvironmentDisplayName" "Info"
    $env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq $EnvironmentDisplayName }
    if (-not $env) { 
        $availableEnvs = (Get-AdminPowerAppEnvironment | Select-Object -ExpandProperty DisplayName) -join ', '
        throw "Environment '$EnvironmentDisplayName' not found in SOURCE. Available: $availableEnvs" 
    }
    Write-MigrationLog "Environment resolved: $($env.EnvironmentName)" "Success"
} catch {
    Write-MigrationLog "Environment resolution failed: $($_.Exception.Message)" "Error"
    throw
}

# Validate user mapping file
try {
    Write-MigrationLog "Validating user mapping CSV file..." "Info"
    
    if (!(Test-Path $UserMappingCsvPath)) { 
        throw "User mapping CSV not found: $UserMappingCsvPath" 
    }
    
    $csvData = Import-Csv $UserMappingCsvPath
    $userCount = ($csvData | Measure-Object).Count
    
    if ($userCount -eq 0) {
        throw "User mapping CSV is empty or has no data rows"
    }
    
    Write-MigrationLog "User mapping CSV validated - $userCount user mappings found" "Success"
} catch {
    Write-MigrationLog "User mapping CSV validation failed: $($_.Exception.Message)" "Error"
    throw
}

try {
    Write-MigrationLog "Uploading user mapping file..." "Info"
    TenantToTenant-UploadUserMappingFile -EnvironmentName $env.EnvironmentName -UserMappingFilePath $UserMappingCsvPath
    Write-MigrationLog "User mapping file uploaded successfully" "Success"
} catch {
    Write-MigrationLog "Failed to upload user mapping file: $($_.Exception.Message)" "Error"
    throw
}

try {
    Write-MigrationLog "Starting migration preparation..." "Info"
    Write-MigrationLog "This process validates the migration and prepares the environment" "Info"
    
    TenantToTenant-PrepareMigration -MigrationId $MigrationId -TargetTenantId $TargetTenantId
    Write-MigrationLog "Migration preparation started successfully" "Success"
} catch {
    Write-MigrationLog "Failed to start migration preparation: $($_.Exception.Message)" "Error"
    throw
}

Write-MigrationLog "Monitoring preparation status (polling every $($Global:PreparePollingInterval)s)..." "Info"
Write-MigrationLog "This may take several minutes to complete" "Info"

$startTime = Get-Date
$maxWaitMinutes = 60 # Maximum wait time

do {
    Start-Sleep -Seconds $Global:PreparePollingInterval
    
    try {
        $st = TenantToTenant-GetMigrationStatus -MigrationId $MigrationId
        $status = $st.Status
        $progress = $st.Progress
        
        $elapsed = [math]::Round((New-TimeSpan -Start $startTime).TotalMinutes, 1)
        Write-MigrationLog "Status: $status | Progress: $progress% | Elapsed: ${elapsed}min" "Info"
        
        # Check for timeout
        if ($elapsed -gt $maxWaitMinutes) {
            Write-MigrationLog "Preparation has exceeded maximum wait time of $maxWaitMinutes minutes" "Warning"
            Write-MigrationLog "Current status: $status ($progress%)" "Warning"
            
            $continue = Read-Host "Continue waiting? (Y/N) [Default: Y]"
            if ($continue -eq "N" -or $continue -eq "n") {
                throw "Preparation monitoring terminated by user after $elapsed minutes"
            }
            $maxWaitMinutes += 30 # Extend timeout
        }
        
    } catch {
        Write-MigrationLog "Error getting migration status: $($_.Exception.Message)" "Error"
        throw
    }
    
} while ($status -in @("NotStarted", "Running", "InProgress", "Queued"))

$totalTime = [math]::Round((New-TimeSpan -Start $startTime).TotalMinutes, 1)
Write-MigrationLog "Preparation completed after ${totalTime} minutes" "Info"
Write-MigrationLog "Final status: $status" $(if ($status -eq "Succeeded") { "Success" } else { "Warning" })

if ($status -eq "Succeeded") {
    Write-MigrationLog "Migration preparation completed successfully!" "Success"
    Write-MigrationLog "The environment is now ready for migration" "Success"
} else {
    Write-MigrationLog "Preparation did not succeed - Status: $status" "Error"
    Write-MigrationLog "Detailed status information:" "Error"
    $st | Format-List | Out-String | Write-MigrationLog -Level "Error"
    
    # Save error details for analysis
    $errorPath = Join-Path $Global:OutputDirectory "preparation-error-details.txt"
    $errorDetails = @"
Power Platform Migration - Preparation Error Details
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Migration ID: $MigrationId
Final Status: $status
Total Time: ${totalTime} minutes

Detailed Status Object:
$($st | Out-String)
"@
    
    $errorDetails | Out-File -FilePath $errorPath -Encoding UTF8
    Write-MigrationLog "Error details saved: $errorPath" "Info"
    
    throw "Migration preparation failed with status: $status"
}

# Save successful preparation details
$preparationPath = Join-Path $Global:OutputDirectory "preparation-success.txt"
$preparationDetails = @"
Power Platform Migration - Preparation Success
Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Migration ID: $MigrationId
Environment: $EnvironmentDisplayName
Total Time: ${totalTime} minutes

Status: PREPARED - Ready for migration execution

Next Steps:
1. Run 06-Migrate-Origin.ps1 to execute the actual migration
2. Migration must be completed within 7 days of preparation
3. Ensure TARGET tenant is ready to receive the migration

Final Status Object:
$($st | Out-String)
"@

$preparationDetails | Out-File -FilePath $preparationPath -Encoding UTF8
Write-MigrationLog "Preparation details saved: $preparationPath" "Info"

Write-MigrationLog "=== NEXT STEPS ===" "Warning"
Write-MigrationLog "1. Execute migration via 06-Migrate-Origin.ps1" "Warning"
Write-MigrationLog "2. IMPORTANT: Migration must complete within 7 days" "Warning"
Write-MigrationLog "3. Ensure TARGET tenant is ready for migration" "Warning"
