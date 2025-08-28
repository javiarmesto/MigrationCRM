
<# 
  00-Prereqs-Setup.ps1
  Purpose: Install required modules and set policies for Power Platform tenant-to-tenant migration
  Run as: Windows PowerShell 5.1 (recommended) inside VS Code
  
  Note: This script sets up all prerequisites according to Microsoft documentation
#>

. .\Config.ps1

Write-MigrationLog "Starting prerequisites setup for Power Platform migration" "Info"

try {
    Write-MigrationLog "Setting execution policy for current user" "Info"
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-MigrationLog "Execution policy set successfully" "Success"
} catch {
    Write-MigrationLog "Failed to set execution policy: $($_.Exception.Message)" "Warning"
    Write-MigrationLog "Continuing setup despite execution policy error (policy may be restricted by admin)" "Warning"
}

Write-MigrationLog "Configuring TLS 1.2 for PSGallery downloads" "Info"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Install-RequiredModule {
    param(
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [switch]$AllowClobber
    )
    
    Write-MigrationLog "Checking module: $ModuleName" "Info"
    
    if (Get-Module -ListAvailable -Name $ModuleName) {
        Write-MigrationLog "Module $ModuleName already installed" "Success"
        return $true
    }
    
    try {
        $installParams = @{
            Name = $ModuleName
            Scope = "CurrentUser"
            Force = $true
        }
        
        if ($AllowClobber) {
            $installParams.AllowClobber = $true
        }
        
        Write-MigrationLog "Installing module: $ModuleName" "Info"
        Install-Module @installParams
        Write-MigrationLog "Successfully installed: $ModuleName" "Success"
        return $true
    } catch {
        Write-MigrationLog "Failed to install $ModuleName`: $($_.Exception.Message)" "Error"
        return $false
    }
}

Write-MigrationLog "Installing required Power Platform modules" "Info"
$requiredSuccess = $true
foreach ($module in $Global:RequiredModules) {
    $success = Install-RequiredModule -ModuleName $module -AllowClobber:($module -eq "Microsoft.PowerApps.PowerShell")
    if (!$success) { $requiredSuccess = $false }
}

Write-MigrationLog "Installing optional modules" "Info"
foreach ($module in $Global:OptionalModules) {
    $success = Install-RequiredModule -ModuleName $module
    if (!$success) {
        Write-MigrationLog "Optional module $module installation failed - continuing anyway" "Warning"
    }
}

if (!$requiredSuccess) {
    Write-MigrationLog "Prerequisites setup failed - some required modules could not be installed" "Error"
    throw "Prerequisites validation failed"
}

Write-MigrationLog "Verifying final module installation" "Info"
$Global:RequiredModules + $Global:OptionalModules | 
    ForEach-Object { Get-Module -ListAvailable -Name $_ } | 
    Where-Object { $_ } | 
    Select-Object Name, Version | 
    Format-Table -AutoSize

Write-MigrationLog "Prerequisites setup completed successfully!" "Success"
Write-MigrationLog "Restart VS Code/PowerShell if this is the first installation" "Warning"
