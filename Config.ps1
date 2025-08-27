<# 
  Config.ps1
  Centralized configuration for Power Platform / Dynamics 365 tenant-to-tenant migration
  
  Usage: 
  - Update the variables below with your specific values
  - Source this file at the beginning of each script: . .\Config.ps1
#>

# === TENANT CONFIGURATION ===
$Global:SourceTenantId = ""           # Source tenant ID (optional for source operations)
$Global:TargetTenantId = "be15784a-bd4f-403e-bbcc-1c5bff5e5999"           # Target tenant ID - REQUIRED
$Global:EnvironmentDisplayName = "myCD-CRMTestMigration"   # Display name of environment to migrate - REQUIRED

# === MIGRATION SETTINGS ===
$Global:MigrationId = ""              # Migration ID (set after submission in script 03)
$Global:SecurityGroupId = ""          # Optional security group ID for migration

# === FILE PATHS ===
$Global:UserMappingCsvPath = ".\usermapping.csv"  # Path to user mapping CSV file
$Global:OutputDirectory = ".\migration-output"    # Base directory for all outputs

# === OUTPUT SUBDIRECTORIES ===
$Global:InventoryOutputDir = Join-Path $Global:OutputDirectory "inventory"
$Global:UsersOutputDir = Join-Path $Global:OutputDirectory "users-check"
$Global:PostMigrationOutputDir = Join-Path $Global:OutputDirectory "post-migration"

# === POLLING SETTINGS ===
$Global:PreparePollingInterval = 20   # Seconds between prepare status checks
$Global:MigrationPollingInterval = 30 # Seconds between migration status checks

# === USER MAPPING SETTINGS ===
$Global:TargetUpnColumn = "TargetUpn" # Column name for target UPN in mapping CSV

# === LOGGING SETTINGS ===
$Global:ErrorActionPreference = "Stop" # Default error action for all scripts
$Global:VerboseLogging = $true         # Enable verbose output

# === REQUIRED MODULES ===
$Global:RequiredModules = @(
    "Microsoft.PowerApps.Administration.PowerShell",
    "Microsoft.PowerApps.PowerShell"
)

$Global:OptionalModules = @(
    "Az",                    # For SAS uploads/downloads
    "Microsoft.Graph"        # For user and license verification
)

# === HELPER FUNCTIONS ===

function Initialize-MigrationDirectories {
    <#
    .SYNOPSIS
    Creates all necessary output directories for the migration process
    #>
    $directories = @(
        $Global:OutputDirectory,
        $Global:InventoryOutputDir,
        $Global:UsersOutputDir,
        $Global:PostMigrationOutputDir
    )
    
    foreach ($dir in $directories) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            if ($Global:VerboseLogging) {
                Write-Host "Created directory: $dir" -ForegroundColor Green
            }
        }
    }
}

function Test-ConfigurationValid {
    <#
    .SYNOPSIS
    Validates that required configuration values are set
    #>
    $errors = @()
    
    if ([string]::IsNullOrWhiteSpace($Global:TargetTenantId)) {
        $errors += "TargetTenantId is required"
    }
    
    if ([string]::IsNullOrWhiteSpace($Global:EnvironmentDisplayName)) {
        $errors += "EnvironmentDisplayName is required"
    }
    
    if ($errors.Count -gt 0) {
        throw "Configuration validation failed: $($errors -join '; ')"
    }
    
    return $true
}

function Get-EnvironmentId {
    <#
    .SYNOPSIS
    Resolves environment display name to environment ID
    .PARAMETER DisplayName
    The display name of the environment
    .OUTPUTS
    Returns the environment ID (EnvironmentName)
    #>
    param(
        [Parameter(Mandatory=$true)][string]$DisplayName
    )
    
    $env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq $DisplayName }
    if (-not $env) { 
        throw "Environment '$DisplayName' not found. Available environments: $(( Get-AdminPowerAppEnvironment | Select-Object -ExpandProperty DisplayName ) -join ', ')"
    }
    
    return $env.EnvironmentName
}

function Write-MigrationLog {
    <#
    .SYNOPSIS
    Standardized logging function for migration scripts
    .PARAMETER Message
    The message to log
    .PARAMETER Level
    Log level: Info, Warning, Error, Success
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("Info", "Warning", "Error", "Success")][string]$Level = "Info"
    )
    
    $colors = @{
        "Info" = "Cyan"
        "Warning" = "Yellow" 
        "Error" = "Red"
        "Success" = "Green"
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

# Auto-initialize directories when config is loaded
Initialize-MigrationDirectories

Write-Host "Migration configuration loaded successfully!" -ForegroundColor Green
Write-Host "Output directory: $Global:OutputDirectory" -ForegroundColor Cyan

# Validate configuration on load
try {
    Test-ConfigurationValid
} catch {
    Write-Warning "Configuration validation failed: $($_.Exception.Message)"
    Write-Host "Please update Config.ps1 with required values before running migration scripts." -ForegroundColor Yellow
}