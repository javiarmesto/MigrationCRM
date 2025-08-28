<#
  MigrationRunbook.ps1
  Master orchestrator for Power Platform tenant-to-tenant migration
  
  Features:
  - Unified execution with checkpoints
  - Rollback capability
  - Comprehensive logging
  - Resume from specific phase
  - Validation between phases
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "Prerequisites", "Inventory", "UsersCheck", "Submit", "Approve", "Prepare", "Migrate", "PostMigration")]
    [string]$Phase = "All",
    
    [ValidateSet("Interactive", "Unattended")]
    [string]$Mode = "Interactive",
    
    [string]$ResumeFromCheckpoint,
    
    [switch]$SkipValidation,
    
    [switch]$DryRun
    ,
    [string]$UserMappingCsvPath
)

# Load configuration
. .\Config.ps1

# Inicializar rutas de log y checkpoint antes de cualquier uso
$Global:RunbookLogFile = Join-Path $Global:OutputDirectory "migration-runbook.log"
$Global:CheckpointFile = Join-Path $Global:OutputDirectory "migration-checkpoint.json"

# Definición de la función antes de cualquier uso
function Write-RunbookLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    $colors = @{
        "INFO" = "White"
        "WARN" = "Yellow"
        "ERROR" = "Red"
        "SUCCESS" = "Green"
        "DEBUG" = "Gray"
    }
    Write-Host $logEntry -ForegroundColor $colors[$Level]
    Add-Content -Path $Global:RunbookLogFile -Value $logEntry -Encoding UTF8
}

# Override user mapping CSV path if parameter is provided (after config load and function definition)
if ($UserMappingCsvPath) {
    $Global:UserMappingCsvPath = $UserMappingCsvPath
    Write-RunbookLog "Using custom user mapping CSV: $Global:UserMappingCsvPath" "INFO"
}

function Save-Checkpoint {
    param(
        [Parameter(Mandatory=$true)][string]$Phase,
        [Parameter(Mandatory=$true)][string]$Status,
        [hashtable]$Data = @{}
    )
    
    $checkpoint = @{
        Phase = $Phase
        Status = $Status
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Data = $Data
    }
    
    $checkpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $Global:CheckpointFile -Encoding UTF8
    Write-RunbookLog "Checkpoint saved: $Phase - $Status" "DEBUG"
}

function Get-Checkpoint {
    if (Test-Path $Global:CheckpointFile) {
        return Get-Content -Path $Global:CheckpointFile -Raw | ConvertFrom-Json
    }
    return $null
}

function Test-Prerequisites {
    Write-RunbookLog "Validating prerequisites..." "INFO"
    
    $requiredModules = $Global:RequiredModules
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (!(Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-RunbookLog "Missing required modules: $($missingModules -join ', ')" "ERROR"
        return $false
    }
    
    # Validate configuration
    try {
        Test-ConfigurationValid
        Write-RunbookLog "Configuration validation passed" "SUCCESS"
        return $true
    } catch {
        Write-RunbookLog "Configuration validation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Invoke-MigrationPhase {
    param(
        [Parameter(Mandatory=$true)][string]$PhaseName,
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [hashtable]$Parameters = @{},
        [string]$Description
    )
    
    Write-RunbookLog "========================================" "INFO"
    Write-RunbookLog "PHASE: $PhaseName" "INFO"
    Write-RunbookLog "SCRIPT: $ScriptPath" "INFO"
    if ($Description) { Write-RunbookLog "DESC: $Description" "INFO" }
    Write-RunbookLog "========================================" "INFO"
    
    if ($DryRun) {
        Write-RunbookLog "DRY RUN: Would execute $ScriptPath with parameters: $($Parameters | ConvertTo-Json -Compress)" "WARN"
        Save-Checkpoint -Phase $PhaseName -Status "DryRun" -Data $Parameters
        return $true
    }
    
    try {
        Save-Checkpoint -Phase $PhaseName -Status "Starting" -Data $Parameters
        
        if (!(Test-Path $ScriptPath)) {
            throw "Script not found: $ScriptPath"
        }
        
        if ($Parameters.Count -gt 0) {
            $paramString = ($Parameters.GetEnumerator() | ForEach-Object { "-$($_.Key) '$($_.Value)'" }) -join " "
            $command = "& '$ScriptPath' $paramString"
        } else {
            $command = "& '$ScriptPath'"
        }
        
        Write-RunbookLog "Executing: $command" "DEBUG"
        Invoke-Expression $command
        
        Save-Checkpoint -Phase $PhaseName -Status "Completed" -Data $Parameters
        Write-RunbookLog "Phase $PhaseName completed successfully" "SUCCESS"
        return $true
        
    } catch {
        Save-Checkpoint -Phase $PhaseName -Status "Failed" -Data @{ Parameters = $Parameters; Error = $_.Exception.Message }
        Write-RunbookLog "Phase $PhaseName failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Request-UserConfirmation {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$DefaultChoice = "Y"
    )
    
    if ($Mode -eq "Unattended") {
        Write-RunbookLog "Unattended mode: Auto-confirming: $Message" "WARN"
        return $true
    }
    
    do {
        Write-Host "$Message [Y/N] (default: $DefaultChoice): " -ForegroundColor Cyan -NoNewline
        $choice = Read-Host
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $DefaultChoice }
        $choice = $choice.ToUpper()
    } while ($choice -notin @("Y", "N"))
    
    return $choice -eq "Y"
}

# Main execution
Write-RunbookLog "Power Platform Migration Runbook Starting" "SUCCESS"
Write-RunbookLog "Phase: $Phase | Mode: $Mode | DryRun: $DryRun" "INFO"
Write-RunbookLog "DEBUG: UserMappingCsvPath parameter received: '$UserMappingCsvPath'" "DEBUG"

# Initialize directories
Initialize-MigrationDirectories

# Override user mapping CSV path if parameter is provided (after config load)
if ($UserMappingCsvPath) {
    $Global:UserMappingCsvPath = $UserMappingCsvPath
    Write-RunbookLog "Using custom user mapping CSV: $Global:UserMappingCsvPath" "INFO"
}

# Handle resume
$resumeFrom = $null
if ($ResumeFromCheckpoint) {
    $checkpoint = Get-Checkpoint
    if ($checkpoint) {
        Write-RunbookLog "Found checkpoint: $($checkpoint.Phase) - $($checkpoint.Status)" "INFO"
        if (Request-UserConfirmation "Resume from checkpoint '$($checkpoint.Phase)'?") {
            $resumeFrom = $checkpoint.Phase
        }
    }
}

# Define migration phases
$phases = [ordered]@{
    "Prerequisites" = @{
        Script = ".\00-Prereqs-Setup.ps1"
        Description = "Install required modules and configure environment"
        RequireConfirmation = $false
    }
    "Inventory" = @{
        Script = ".\01-Inventory-And-Sanitation-Origin.ps1"
        Description = "Create inventory of flows, apps, and connectors in source environment"
        Parameters = @{ EnvironmentDisplayName = $Global:EnvironmentDisplayName }
        RequireConfirmation = $true
    }
    "UsersCheck" = @{
        Script = ".\02-Users-And-Licenses-Check-Destination.ps1"
        Description = "Verify users and licenses in target tenant"
        Parameters = @{ 
            UserMappingCsvPath = $Global:UserMappingCsvPath
            TargetUpnColumn = $Global:TargetUpnColumn 
        }
        RequireConfirmation = $true
    }
    "Submit" = @{
        Script = ".\03-Submit-Migration-Origin.ps1"
        Description = "Submit migration request from source tenant"
        Parameters = @{ 
            EnvironmentDisplayName = $Global:EnvironmentDisplayName
            TargetTenantId = $Global:TargetTenantId 
        }
        RequireConfirmation = $true
    }
    "Approve" = @{
        Script = ".\04-Approve-Migration-Destination.ps1"
        Description = "Approve migration request in target tenant"
        Parameters = @{ TargetTenantId = $Global:TargetTenantId }
        RequireConfirmation = $true
    }
    "Prepare" = @{
        Script = ".\05-UploadMapping-Prepare-Origin.ps1"
        Description = "Upload user mapping and prepare migration"
        Parameters = @{ 
            EnvironmentDisplayName = $Global:EnvironmentDisplayName
            MigrationId = $Global:MigrationId
            TargetTenantId = $Global:TargetTenantId
            UserMappingCsvPath = $Global:UserMappingCsvPath
        }
        RequireConfirmation = $true
    }
    "Migrate" = @{
        Script = ".\06-Migrate-Origin.ps1"
        Description = "Execute the actual migration"
        Parameters = @{ 
            MigrationId = $Global:MigrationId
            TargetTenantId = $Global:TargetTenantId
            SecurityGroupId = $Global:SecurityGroupId
        }
        RequireConfirmation = $true
    }
    "PostMigration" = @{
        Script = ".\07-PostMigration-Flow-Assist-Destination.ps1"
        Description = "Post-migration tasks: enable flows and verify migration"
        Parameters = @{ 
            EnvironmentDisplayName = $Global:EnvironmentDisplayName
            TargetTenantId = $Global:TargetTenantId
        }
        RequireConfirmation = $false
    }
}

Write-RunbookLog "DEBUG: UserMappingCsvPath usado en fase: $($phases['UsersCheck'].Parameters.UserMappingCsvPath)" "DEBUG"

# Prerequisites validation
if (!$SkipValidation -and !(Test-Prerequisites)) {
    Write-RunbookLog "Prerequisites validation failed. Run with -Phase Prerequisites first." "ERROR"
    exit 1
}

# Execute phases
$success = $true
$phasesToRun = if ($Phase -eq "All") { $phases.Keys } else { @($Phase) }

foreach ($phaseName in $phasesToRun) {
    # Skip if resuming and haven't reached resume point
    if ($resumeFrom -and $phaseName -ne $resumeFrom) {
        continue
    } else {
        $resumeFrom = $null # Clear resume flag once we reach the point
    }
    
    $phaseInfo = $phases[$phaseName]
    
    # Confirmation for critical phases
    if ($phaseInfo.RequireConfirmation -and $Mode -eq "Interactive") {
        $message = "Execute phase '$phaseName': $($phaseInfo.Description)?"
        if (!(Request-UserConfirmation $message)) {
            Write-RunbookLog "Phase '$phaseName' skipped by user" "WARN"
            continue
        }
    }
    
    # Special handling for phases that need dynamic parameters
    $parameters = if ($phaseInfo.Parameters) { $phaseInfo.Parameters } else { @{} }
    
    # Override UserMappingCsvPath if custom parameter was provided
    if ($UserMappingCsvPath -and $parameters.ContainsKey('UserMappingCsvPath')) {
        $parameters.UserMappingCsvPath = $UserMappingCsvPath
        Write-RunbookLog "Overriding UserMappingCsvPath for this phase: $UserMappingCsvPath" "INFO"
    }
    
    # Execute phase
    $result = Invoke-MigrationPhase -PhaseName $phaseName -ScriptPath $phaseInfo.Script -Parameters $parameters -Description $phaseInfo.Description
    
    if (!$result) {
        $success = $false
        Write-RunbookLog "Migration failed at phase: $phaseName" "ERROR"
        
        if ($Mode -eq "Interactive") {
            if (Request-UserConfirmation "Continue with next phase despite failure?" "N") {
                continue
            }
        }
        break
    }
    
    # Brief pause between phases for logging visibility
    if ($Mode -eq "Interactive" -and $phaseName -ne $phasesToRun[-1]) {
        Start-Sleep -Seconds 2
    }
}

# Summary
Write-RunbookLog "========================================" "INFO"
if ($success) {
    Write-RunbookLog "MIGRATION RUNBOOK COMPLETED SUCCESSFULLY!" "SUCCESS"
} else {
    Write-RunbookLog "MIGRATION RUNBOOK FAILED!" "ERROR"
}
Write-RunbookLog "Log file: $Global:RunbookLogFile" "INFO"
Write-RunbookLog "Checkpoint file: $Global:CheckpointFile" "INFO"
Write-RunbookLog "========================================" "INFO"

if (!$success) { exit 1 }