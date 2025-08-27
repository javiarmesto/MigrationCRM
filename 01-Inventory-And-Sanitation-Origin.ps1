
<# 
  01-Inventory-And-Sanitation-Origin.ps1
  Purpose: Connect to SOURCE tenant, locate environment, and produce inventory CSVs for flows, apps, and custom connectors.
  Notes:
   - Uses Microsoft.PowerApps.Administration.PowerShell
   - Canvas apps export is typically manual from Maker portal; this script lists Canvas apps to help you find them.
   - Only supports production and sandbox environments per Microsoft documentation
#>

param(
  [Parameter(Mandatory=$false)][string]$EnvironmentDisplayName
)

. .\Config.ps1

# Use environment from config if not provided as parameter
if ([string]::IsNullOrWhiteSpace($EnvironmentDisplayName)) {
    $EnvironmentDisplayName = $Global:EnvironmentDisplayName
    if ([string]::IsNullOrWhiteSpace($EnvironmentDisplayName)) {
        throw "EnvironmentDisplayName must be provided via parameter or Config.ps1"
    }
}

Write-MigrationLog "Starting inventory and sanitation for environment: $EnvironmentDisplayName" "Info"

try {
    Write-MigrationLog "Connecting to SOURCE tenant..." "Info"
    Add-PowerAppsAccount -Endpoint prod | Out-Null
    Write-MigrationLog "Successfully connected to SOURCE tenant" "Success"
} catch {
    Write-MigrationLog "Failed to connect to SOURCE tenant: $($_.Exception.Message)" "Error"
    throw
}

try {
    Write-MigrationLog "Resolving environment ID for: $EnvironmentDisplayName" "Info"
    $env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq $EnvironmentDisplayName }
    if (-not $env) { 
        $availableEnvs = (Get-AdminPowerAppEnvironment | Select-Object -ExpandProperty DisplayName) -join ', '
        throw "Environment '$EnvironmentDisplayName' not found in SOURCE. Available: $availableEnvs" 
    }
    
    # Validate environment type (only production and sandbox supported)
    if ($env.EnvironmentType -notin @('Production', 'Sandbox')) {
        throw "Environment type '$($env.EnvironmentType)' is not supported. Only Production and Sandbox environments can be migrated."
    }
    
    $ENV_ID = $env.EnvironmentName
    Write-MigrationLog "Environment resolved - Name: $ENV_ID, Type: $($env.EnvironmentType)" "Success"
} catch {
    Write-MigrationLog "Environment resolution failed: $($_.Exception.Message)" "Error"
    throw
}

$outDir = $Global:InventoryOutputDir
Write-MigrationLog "Output directory: $outDir" "Info"

# 1) Flows (solution-aware flag via SolutionId)
Write-MigrationLog "Exporting flow inventory..." "Info"
try {
    $flows = Get-AdminFlow -EnvironmentName $ENV_ID
    $flowCount = ($flows | Measure-Object).Count
    Write-MigrationLog "Found $flowCount flows" "Info"
    
    $flows | Select-Object DisplayName, Enabled, SolutionId, FlowName, CreatedTime, LastModifiedTime, CreatedBy |
        Export-Csv (Join-Path $outDir "flows.csv") -NoTypeInformation -Encoding UTF8
    
    # Identify solution-aware vs non-solution flows
    $solutionFlows = ($flows | Where-Object { ![string]::IsNullOrWhiteSpace($_.SolutionId) } | Measure-Object).Count
    $nonSolutionFlows = $flowCount - $solutionFlows
    
    Write-MigrationLog "Flow analysis: $solutionFlows solution-aware, $nonSolutionFlows non-solution" "Info"
    if ($nonSolutionFlows -gt 0) {
        Write-MigrationLog "WARNING: $nonSolutionFlows flows are not solution-aware and may need manual migration" "Warning"
    }
} catch {
    Write-MigrationLog "Failed to export flows: $($_.Exception.Message)" "Error"
    throw
}

# 2) Apps (Canvas/Model-driven)
Write-MigrationLog "Exporting app inventory..." "Info"
try {
    $apps = Get-AdminPowerApp -EnvironmentName $ENV_ID
    $appCount = ($apps | Measure-Object).Count
    Write-MigrationLog "Found $appCount apps" "Info"
    
    $apps | Select-Object DisplayName, AppName, AppType, CreatedTime, LastModifiedTime, Owner |
        Export-Csv (Join-Path $outDir "apps.csv") -NoTypeInformation -Encoding UTF8
    
    # Analyze app types
    $appsByType = $apps | Group-Object AppType
    foreach ($group in $appsByType) {
        Write-MigrationLog "$($group.Name) apps: $($group.Count)" "Info"
    }
} catch {
    Write-MigrationLog "Failed to export apps: $($_.Exception.Message)" "Error"
    throw
}

# 3) Connectors (Custom connectors)
Write-MigrationLog "Exporting custom connectors inventory..." "Info"
$connectors = $null
try {
    try {
        $connectors = Get-AdminPowerAppConnector -EnvironmentName $ENV_ID -ErrorAction Stop
    } catch {
        try {
            $connectors = Get-AdminConnector -EnvironmentName $ENV_ID -ErrorAction Stop
        } catch {
            Write-MigrationLog "No admin connector cmdlet available. Custom connectors must be documented manually from Maker portal (Data > Custom connectors)." "Warning"
        }
    }
    
    if ($connectors) {
        $connectorCount = ($connectors | Measure-Object).Count
        Write-MigrationLog "Found $connectorCount custom connectors" "Info"
        
        $connectors | Select-Object Name, DisplayName, ConnectorType, CreatedTime, Owner |
            Export-Csv (Join-Path $outDir "custom-connectors.csv") -NoTypeInformation -Encoding UTF8
    } else {
        Write-MigrationLog "No custom connectors found or cmdlet unavailable" "Info"
        # Create empty CSV for consistency
        "Name,DisplayName,ConnectorType,CreatedTime,Owner" | Out-File (Join-Path $outDir "custom-connectors.csv") -Encoding UTF8
    }
} catch {
    Write-MigrationLog "Error during custom connector export: $($_.Exception.Message)" "Warning"
    # Create empty CSV for consistency
    "Name,DisplayName,ConnectorType,CreatedTime,Owner" | Out-File (Join-Path $outDir "custom-connectors.csv") -Encoding UTF8
}

Write-MigrationLog "Inventory export completed successfully" "Success"
Write-MigrationLog "Output location: $outDir" "Info"

Write-MigrationLog "=== NEXT STEPS REQUIRED ===" "Warning"
Write-MigrationLog "1. Review flows.csv - Ensure critical flows are inside Solutions (SolutionId column)" "Warning"
Write-MigrationLog "2. Export Canvas Apps/Custom Pages manually from Maker portal and remove from SOURCE before migration" "Warning"
Write-MigrationLog "3. Export Custom Connector packages from Maker portal (Data > Custom connectors)" "Warning"
Write-MigrationLog "4. Prepare user mapping CSV file for the next phase" "Warning"

# Generate summary report
$summaryPath = Join-Path $outDir "inventory-summary.txt"
$summary = @"
Power Platform Migration - Inventory Summary
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Environment: $EnvironmentDisplayName ($ENV_ID)
Environment Type: $($env.EnvironmentType)

Files Generated:
- flows.csv
- apps.csv  
- custom-connectors.csv

Next Steps:
1. Review all CSV files for completeness
2. Ensure critical flows are solution-aware
3. Manually export Canvas apps and custom connectors
4. Proceed to user validation phase
"@

$summary | Out-File -FilePath $summaryPath -Encoding UTF8
Write-MigrationLog "Summary report saved: $summaryPath" "Info"
