# Troubleshooting Guide

> **🌐 Language:** **English** | [Español](../es/solucion-problemas.md)

Comprehensive troubleshooting guide for Power Platform tenant-to-tenant migration issues.

## 🔍 Quick Diagnostics

### Health Check Commands
```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Verify modules
Get-Module -ListAvailable Microsoft.PowerApps*

# Test authentication
Add-PowerAppsAccount -Endpoint prod
Get-AdminPowerAppEnvironment | Select-Object -First 1

# Check current context
whoami
```

---

## 🚨 Common Issues by Phase

### Phase 1: Prerequisites Setup

#### Issue: Module Installation Fails
**Symptoms:**
- `Install-Module` throws access denied errors
- PowerShell Gallery connection fails

**Solutions:**
```powershell
# Run as Administrator
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Use different scope
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force

# Clear module cache
Remove-Module Microsoft.PowerApps* -Force -ErrorAction SilentlyContinue
```

#### Issue: TLS/SSL Errors
**Symptoms:**
- "Unable to resolve package source" errors
- SSL connection failures

**Solutions:**
```powershell
# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Trust PSGallery
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
```

### Phase 2: Environment Inventory

#### Issue: Environment Not Found
**Symptoms:**
- "Environment 'X' not found in SOURCE"
- Empty environment list

**Diagnostic Steps:**
```powershell
# List all environments
Get-AdminPowerAppEnvironment | Format-Table DisplayName, EnvironmentName, EnvironmentType

# Check permissions
Get-AdminPowerAppRoleAssignment -UserId (Get-AzContext).Account.Id

# Verify authentication context
Get-PowerAppsAccount
```

**Solutions:**
- Verify exact spelling of environment name
- Ensure user has Environment Admin or Power Platform Admin role
- Check if connected to correct tenant

#### Issue: Access Denied to Environment
**Symptoms:**
- 403 Forbidden errors
- "Insufficient privileges" messages

**Solutions:**
```powershell
# Check role assignments
Get-AdminPowerAppEnvironmentRoleAssignment -EnvironmentName $envId

# Request access from environment owner
# Verify tenant context with Get-AzTenant
```

### Phase 3: User Validation

#### Issue: Microsoft Graph Connection Fails
**Symptoms:**
- Graph authentication prompts repeatedly
- Permission consent errors

**Solutions:**
```powershell
# Clear Graph session
Disconnect-MgGraph -ErrorAction SilentlyContinue

# Connect with specific scopes
Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All" -NoWelcome

# Check Graph context
Get-MgContext
```

#### Issue: Users Not Found in Target
**Symptoms:**
- High percentage of missing users
- "User principal name does not exist"

**Diagnostic Steps:**
```powershell
# Test specific user
Get-MgUser -Filter "userPrincipalName eq 'test@target.com'"

# Check tenant domain
Get-MgDomain | Where-Object {$_.IsDefault -eq $true}

# Verify CSV format
Import-Csv .\usermapping.csv | Select-Object -First 5
```

### Phase 4-5: Migration Request & Approval

#### Issue: Submit Migration Request Fails
**Symptoms:**
- "Environment type not supported"
- "Target tenant not found"

**Diagnostic Steps:**
```powershell
# Verify environment type
$env = Get-AdminPowerAppEnvironment -EnvironmentName $envId
Write-Host "Environment Type: $($env.EnvironmentType)"

# Test target tenant ID format
$targetId = "12345678-1234-5678-9012-123456789012"  # Must be valid GUID
[System.Guid]::Parse($targetId)
```

**Solutions:**
- Only Production and Sandbox environments supported
- Verify target tenant ID is correct GUID format
- Ensure cross-tenant permissions are configured

#### Issue: No Migration Requests Visible
**Symptoms:**
- `TenantToTenant-ViewMigrationRequest` returns empty
- "No pending requests found"

**Solutions:**
```powershell
# Verify connected to correct target tenant
Add-PowerAppsAccount -Endpoint prod -TenantID $targetTenantId

# Check all requests (may be approved/rejected already)
TenantToTenant-ViewMigrationRequest -TenantID $targetTenantId | Format-List

# Wait for request propagation (can take 5-10 minutes)
```

### Phase 6-7: Preparation & Migration

#### Issue: User Mapping Upload Fails
**Symptoms:**
- CSV upload errors
- "Invalid file format" messages

**Diagnostic Steps:**
```powershell
# Validate CSV structure
$csv = Import-Csv .\usermapping.csv
$csv | Get-Member
$csv | Where-Object {[string]::IsNullOrWhiteSpace($_.TargetUpn)}

# Check file encoding
Get-Content .\usermapping.csv -Encoding UTF8 | Select-Object -First 5
```

**Solutions:**
- Ensure CSV has SourceUpn,TargetUpn headers
- Save CSV with UTF-8 encoding
- Remove empty rows and special characters
- Validate all email addresses are properly formatted

#### Issue: Migration Stuck/Timeout
**Symptoms:**
- Progress stuck at same percentage
- No status updates for extended periods

**Monitoring Commands:**
```powershell
# Detailed status monitoring
do {
    $status = TenantToTenant-GetMigrationStatus -MigrationId $migrationId
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Status: $($status.Status) | Progress: $($status.Progress)%"
    
    if ($status.Status -in @("Failed", "Succeeded")) { break }
    Start-Sleep -Seconds 60
} while ($true)
```

**Solutions:**
- Large environments can take 8+ hours
- Check Microsoft service health
- Verify sufficient capacity in target tenant
- Monitor for specific error messages in status object

### Phase 8: Post-Migration

#### Issue: Flows Won't Enable
**Symptoms:**
- "Could not enable flow" messages
- Connection reference errors

**Diagnostic Steps:**
```powershell
# Check connection references
Get-AdminPowerAppConnectionReferences -EnvironmentName $envId | Where-Object {$_.Status -ne "Connected"}

# List connectors
Get-AdminPowerAppConnector -EnvironmentName $envId | Format-Table
```

**Solutions:**
- Re-authenticate all connection references in admin portal
- Verify custom connectors are available in target tenant
- Check if connectors require different authentication in target
- Enable flows manually through Power Platform admin center

---

## 🔧 Advanced Diagnostics

### PowerShell Session Issues
```powershell
# Clear all variables and restart clean
Remove-Variable * -ErrorAction SilentlyContinue
Clear-History
Import-Module Microsoft.PowerApps.Administration.PowerShell -Force

# Check module conflicts
Get-Module | Where-Object {$_.Name -like "*PowerApps*"}
```

### Network Connectivity
```powershell
# Test PowerApps service connectivity
Test-NetConnection -ComputerName api.powerapps.com -Port 443

# Check proxy settings
netsh winhttp show proxy

# Test authentication endpoints
Invoke-WebRequest -Uri "https://login.microsoftonline.com" -UseBasicParsing
```

### Performance Issues
```powershell
# Monitor memory usage
Get-Process PowerShell | Select-Object WorkingSet, VirtualMemorySize

# Check disk space
Get-WmiObject -Class Win32_LogicalDisk | Select-Object DeviceID, Size, FreeSpace

# Network performance
Test-NetConnection -ComputerName api.bap.microsoft.com -Port 443 -InformationLevel Detailed
```

---

## 📊 Log Analysis Techniques

### Reading Migration Logs
```powershell
# Filter by error level
Select-String -Path "migration-output\migration-runbook.log" -Pattern "ERROR"

# Get last 50 entries
Get-Content "migration-output\migration-runbook.log" -Tail 50

# Find specific phase issues
Select-String -Path "migration-output\migration-runbook.log" -Pattern "Phase.*failed"
```

### PowerShell Transcript Analysis
```powershell
# Enable detailed logging
Start-Transcript -Path "migration-debug.txt"
# ... run migration commands ...
Stop-Transcript

# Analyze transcript
Select-String -Path "migration-debug.txt" -Pattern "Exception|Error|Failed"
```

---

## 🆘 Escalation Procedures

### Microsoft Support Information
When contacting Microsoft Support, provide:
- Migration ID
- Tenant IDs (source and target)
- Environment ID
- Exact error messages
- PowerShell transcript logs
- Timeline of when issues occurred

### Community Resources
- [Power Platform Community Forums](https://powerusers.microsoft.com/t5/Power-Platform-Administration/bd-p/PA_Admin)
- [Microsoft Tech Community](https://techcommunity.microsoft.com/t5/power-platform/ct-p/PowerPlatform)
- [Power Platform GitHub Issues](https://github.com/MicrosoftDocs/power-platform)

---

## 🔄 Recovery Procedures

### Rollback Strategy
If migration fails midway:
1. **DO NOT** attempt to restart migration immediately
2. Document current state and error messages
3. Review migration status object for specific failure points
4. Contact Microsoft Support for guidance on cleanup
5. Plan recovery timeline (7-day window still applies)

### Cleanup Commands
```powershell
# Clear failed migration state (use with caution)
# This should only be done with Microsoft Support guidance
$status = TenantToTenant-GetMigrationStatus -MigrationId $migrationId
if ($status.Status -eq "Failed") {
    # Document everything before cleanup
    $status | ConvertTo-Json -Depth 10 | Out-File "failure-details.json"
}
```

---

**🔗 Related Documentation:**
- [Best Practices](best-practices.md)
- [API Reference](api-reference.md)
- [Microsoft Official Troubleshooting](https://docs.microsoft.com/en-us/power-platform/admin/troubleshooting-common-issues)

---

**🌐 Available in:** **English** | [Español](../es/solucion-problemas.md)