
<# 
  03-Submit-Migration-Origin.ps1
  Purpose: Submit migration request from SOURCE tenant to TARGET tenant
  Note: This initiates the tenant-to-tenant migration process
#>

param(
  [Parameter(Mandatory=$false)][string]$EnvironmentDisplayName,
  [Parameter(Mandatory=$false)][string]$TargetTenantId
)

. .\Config.ps1

# Use config values if parameters not provided
if ([string]::IsNullOrWhiteSpace($EnvironmentDisplayName)) {
    $EnvironmentDisplayName = $Global:EnvironmentDisplayName
}
if ([string]::IsNullOrWhiteSpace($TargetTenantId)) {
    $TargetTenantId = $Global:TargetTenantId
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($EnvironmentDisplayName) -or [string]::IsNullOrWhiteSpace($TargetTenantId)) {
    Write-MigrationLog "EnvironmentDisplayName and TargetTenantId are required" "Error"
    throw "Missing required parameters - check Config.ps1 or provide via parameters"
}

Write-MigrationLog "Starting migration submission process" "Info"
Write-MigrationLog "Source Environment: $EnvironmentDisplayName" "Info"
Write-MigrationLog "Target Tenant ID: $TargetTenantId" "Info"

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
    
    # Validate environment type again before submission
    if ($env.EnvironmentType -notin @('Production', 'Sandbox')) {
        throw "Environment type '$($env.EnvironmentType)' is not supported for tenant-to-tenant migration. Only Production and Sandbox environments are supported."
    }
    
    $ENV_ID = $env.EnvironmentName
    Write-MigrationLog "Environment resolved - ID: $ENV_ID, Type: $($env.EnvironmentType)" "Success"
} catch {
    Write-MigrationLog "Environment resolution failed: $($_.Exception.Message)" "Error"
    throw
}

try {
    Write-MigrationLog "Submitting migration request..." "Info"
    Write-MigrationLog "This will initiate the tenant-to-tenant migration process" "Warning"
    
    TenantToTenant-SubmitMigrationRequest -EnvironmentName $ENV_ID -TargetTenantID $TargetTenantId
    
    Write-MigrationLog "Migration request submitted successfully!" "Success"
    Write-MigrationLog "Environment: $ENV_ID" "Info"
    Write-MigrationLog "Target Tenant: $TargetTenantId" "Info"
    
} catch {
    Write-MigrationLog "Failed to submit migration request: $($_.Exception.Message)" "Error"
    throw
}

Write-MigrationLog "=== NEXT STEPS REQUIRED ===" "Warning"
Write-MigrationLog "1. TARGET tenant admin must approve this migration request" "Warning"
Write-MigrationLog "2. Run script 04-Approve-Migration-Destination.ps1 in the TARGET tenant" "Warning"
Write-MigrationLog "3. After approval, note the MigrationId for subsequent steps" "Warning"

# Save submission details for reference
$submissionPath = Join-Path $Global:OutputDirectory "migration-submission.txt"
$submissionDetails = @"
Power Platform Migration - Submission Details
Submitted: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source Environment: $EnvironmentDisplayName ($ENV_ID)
Source Environment Type: $($env.EnvironmentType)
Target Tenant ID: $TargetTenantId

Status: SUBMITTED - Awaiting approval from target tenant

Next Steps:
1. TARGET tenant admin must approve via 04-Approve-Migration-Destination.ps1
2. Obtain MigrationId after approval
3. Update Config.ps1 with the MigrationId
4. Proceed to preparation phase
"@

$submissionDetails | Out-File -FilePath $submissionPath -Encoding UTF8
Write-MigrationLog "Submission details saved: $submissionPath" "Info"
