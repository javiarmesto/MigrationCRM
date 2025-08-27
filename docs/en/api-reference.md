# Power Platform Migration API Reference

> **🌐 Language:** **English** | [Español](../es/referencia-api.md)

Complete reference for all PowerShell cmdlets used in the Power Platform tenant-to-tenant migration process.

## 📚 Table of Contents

- [Authentication Cmdlets](#authentication-cmdlets)
- [Migration Request Cmdlets](#migration-request-cmdlets)
- [Environment Management](#environment-management)
- [User Mapping](#user-mapping)
- [Status Monitoring](#status-monitoring)
- [Helper Functions](#helper-functions)
- [Error Handling](#error-handling)

---

## Authentication Cmdlets

### Add-PowerAppsAccount

Authenticates to Power Platform services.

```powershell
Add-PowerAppsAccount -Endpoint prod [-TenantID <tenant-id>]
```

**Parameters:**
- `Endpoint` - Service endpoint (always use 'prod' for production)
- `TenantID` (Optional) - Specific tenant ID for multi-tenant scenarios

**Example:**
```powershell
# Connect to source tenant
Add-PowerAppsAccount -Endpoint prod

# Connect to specific target tenant
Add-PowerAppsAccount -Endpoint prod -TenantID "12345678-1234-5678-9012-123456789012"
```

**Returns:** Authentication session object

**Common Errors:**
- `AADSTS50020` - User account not found in tenant
- `AADSTS65001` - User hasn't consented to app permissions

---

## Migration Request Cmdlets

### TenantToTenant-SubmitMigrationRequest

Initiates migration request from source tenant.

```powershell
TenantToTenant-SubmitMigrationRequest -EnvironmentName <env-id> -TargetTenantID <tenant-id>
```

**Parameters:**
- `EnvironmentName` - GUID of source environment
- `TargetTenantID` - GUID of target tenant

**Example:**
```powershell
TenantToTenant-SubmitMigrationRequest `
    -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef" `
    -TargetTenantID "12345678-1234-5678-9012-123456789012"
```

**Returns:** Migration request object with RequestID

**Prerequisites:**
- Must be authenticated to source tenant
- Environment must be Production or Sandbox type
- User must have Environment Admin or Power Platform Admin role

---

### TenantToTenant-ViewMigrationRequest

Views pending migration requests in target tenant.

```powershell
TenantToTenant-ViewMigrationRequest -TenantID <tenant-id>
```

**Parameters:**
- `TenantID` - Target tenant ID

**Example:**
```powershell
$requests = TenantToTenant-ViewMigrationRequest -TenantID "12345678-1234-5678-9012-123456789012"
$requests | Format-List
```

**Returns:** Array of pending migration request objects

**Properties returned:**
- `MigrationId` - Unique migration identifier
- `SourceEnvironmentId` - Source environment GUID
- `SourceTenantId` - Source tenant GUID  
- `RequestedDate` - When request was submitted
- `Status` - Current request status

---

### TenantToTenant-ManageMigrationRequest

Approves or rejects migration request in target tenant.

```powershell
TenantToTenant-ManageMigrationRequest -MigrationId <migration-id> [-Approve] [-Reject]
```

**Parameters:**
- `MigrationId` - Migration ID from ViewMigrationRequest
- `Approve` - Switch to approve the request
- `Reject` - Switch to reject the request

**Example:**
```powershell
# Approve migration
TenantToTenant-ManageMigrationRequest -MigrationId "abc123" -Approve

# Reject migration
TenantToTenant-ManageMigrationRequest -MigrationId "abc123" -Reject
```

**Returns:** Updated migration request object

---

## Environment Management

### Get-AdminPowerAppEnvironment

Retrieves Power Platform environments.

```powershell
Get-AdminPowerAppEnvironment [[-EnvironmentName] <env-id>]
```

**Parameters:**
- `EnvironmentName` (Optional) - Specific environment ID

**Example:**
```powershell
# Get all environments
$environments = Get-AdminPowerAppEnvironment

# Get specific environment
$env = Get-AdminPowerAppEnvironment -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef"

# Find environment by display name
$env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq "Production" }
```

**Returns:** Environment object(s) with properties:
- `EnvironmentName` - Unique environment ID (GUID)
- `DisplayName` - Human-readable name
- `EnvironmentType` - Production, Sandbox, Developer, etc.
- `Location` - Geographic region
- `CreatedBy` - Creator information

---

### Get-AdminFlow

Retrieves Power Automate flows from environment.

```powershell
Get-AdminFlow -EnvironmentName <env-id>
```

**Parameters:**
- `EnvironmentName` - Environment ID

**Example:**
```powershell
$flows = Get-AdminFlow -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef"
$flows | Where-Object { $_.Enabled -eq $false } | Select-Object DisplayName, SolutionId
```

**Returns:** Array of flow objects with properties:
- `FlowName` - Unique flow identifier
- `DisplayName` - Flow display name
- `Enabled` - Boolean enabled status
- `SolutionId` - Solution ID (null if not solution-aware)
- `CreatedTime` - Creation timestamp
- `LastModifiedTime` - Last modification timestamp

---

## User Mapping

### TenantToTenant-UploadUserMappingFile

Uploads user mapping CSV to migration storage.

```powershell
TenantToTenant-UploadUserMappingFile -EnvironmentName <env-id> -UserMappingFilePath <csv-path>
```

**Parameters:**
- `EnvironmentName` - Source environment ID
- `UserMappingFilePath` - Full path to CSV file

**Example:**
```powershell
TenantToTenant-UploadUserMappingFile `
    -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef" `
    -UserMappingFilePath "C:\Migration\usermapping.csv"
```

**CSV Format Required:**
```csv
SourceUpn,TargetUpn
user1@source.com,user1@target.com
user2@source.com,user2@target.com
```

**Returns:** Upload confirmation object

---

## Migration Execution

### TenantToTenant-PrepareMigration

Prepares environment for migration.

```powershell
TenantToTenant-PrepareMigration -MigrationId <migration-id> -TargetTenantId <tenant-id>
```

**Parameters:**
- `MigrationId` - Migration ID from approval step
- `TargetTenantId` - Target tenant ID

**Example:**
```powershell
TenantToTenant-PrepareMigration `
    -MigrationId "abc123def456" `
    -TargetTenantId "12345678-1234-5678-9012-123456789012"
```

**Returns:** Preparation job object

**Duration:** Typically 10-30 minutes depending on environment size

---

### TenantToTenant-MigratePowerAppEnvironment

Executes the actual migration.

```powershell
TenantToTenant-MigratePowerAppEnvironment -MigrationId <migration-id> -TargetTenantId <tenant-id> [-SecurityGroupId <group-id>]
```

**Parameters:**
- `MigrationId` - Migration ID
- `TargetTenantId` - Target tenant ID
- `SecurityGroupId` (Optional) - Security group for environment access

**Example:**
```powershell
# Basic migration
TenantToTenant-MigratePowerAppEnvironment `
    -MigrationId "abc123def456" `
    -TargetTenantId "12345678-1234-5678-9012-123456789012"

# With security group
TenantToTenant-MigratePowerAppEnvironment `
    -MigrationId "abc123def456" `
    -TargetTenantId "12345678-1234-5678-9012-123456789012" `
    -SecurityGroupId "sg-98765432-1234-5678-9012-123456789012"
```

**Returns:** Migration job object

**Duration:** 1-8 hours depending on environment complexity

---

## Status Monitoring

### TenantToTenant-GetMigrationStatus

Monitors migration progress.

```powershell
TenantToTenant-GetMigrationStatus -MigrationId <migration-id>
```

**Parameters:**
- `MigrationId` - Migration ID to monitor

**Example:**
```powershell
$status = TenantToTenant-GetMigrationStatus -MigrationId "abc123def456"
Write-Host "Status: $($status.Status) - Progress: $($status.Progress)%"
```

**Returns:** Status object with properties:
- `Status` - Current phase (NotStarted, Running, InProgress, Succeeded, Failed)
- `Progress` - Percentage complete (0-100)
- `StartTime` - Migration start timestamp
- `EstimatedEndTime` - Estimated completion time
- `ErrorDetails` - Error information if failed

**Status Values:**
- `NotStarted` - Migration queued but not begun
- `Running` / `InProgress` - Migration actively processing
- `Succeeded` - Migration completed successfully
- `Failed` - Migration encountered errors
- `Queued` - Waiting for resources

---

## Helper Functions (Config.ps1)

### Test-ConfigurationValid

Validates configuration parameters.

```powershell
Test-ConfigurationValid
```

**Validates:**
- `$Global:TargetTenantId` is set
- `$Global:EnvironmentDisplayName` is set
- Required file paths exist

**Returns:** Boolean (true/false)

**Throws:** Configuration validation errors

---

### Get-EnvironmentId

Resolves environment display name to GUID.

```powershell
Get-EnvironmentId -DisplayName <environment-name>
```

**Parameters:**
- `DisplayName` - Environment display name

**Example:**
```powershell
$envId = Get-EnvironmentId -DisplayName "Production CRM"
```

**Returns:** Environment GUID string

---

### Write-MigrationLog

Standardized logging function.

```powershell
Write-MigrationLog -Message <message> [-Level <level>]
```

**Parameters:**
- `Message` - Log message text
- `Level` - Log level (Info, Warning, Error, Success)

**Example:**
```powershell
Write-MigrationLog "Migration started" "Info"
Write-MigrationLog "Connection failed" "Error"
Write-MigrationLog "Phase completed" "Success"
```

**Output:** Console + log file

---

## Error Handling

### Common Error Codes

| Error Code | Description | Solution |
|------------|-------------|----------|
| `EnvironmentNotFound` | Environment doesn't exist | Verify environment name and permissions |
| `InvalidEnvironmentType` | Environment type not supported | Use only Production or Sandbox |
| `UserMappingInvalid` | CSV format incorrect | Check CSV structure and encoding |
| `MigrationTimeout` | Migration exceeded time limit | Check environment size and retry |
| `InsufficientPermissions` | User lacks required permissions | Verify admin roles |
| `TenantNotFound` | Target tenant doesn't exist | Verify tenant ID |

### Error Recovery Patterns

**Authentication Errors:**
```powershell
# Clear session and reconnect
Clear-Variable -Name * -Scope Global -ErrorAction SilentlyContinue
Add-PowerAppsAccount -Endpoint prod
```

**Timeout Errors:**
```powershell
# Check status and resume
$status = TenantToTenant-GetMigrationStatus -MigrationId $migrationId
if ($status.Status -eq "Failed") {
    # Review error details and retry preparation
}
```

**Permission Errors:**
```powershell
# Verify role assignments
Get-AdminPowerAppRoleAssignment -EnvironmentName $envId
```

---

## Rate Limits and Throttling

- **API calls:** 600 requests per hour per user
- **Concurrent migrations:** 1 per tenant pair
- **Retry intervals:** 30 seconds minimum between status checks

## SDK Versions

- **Microsoft.PowerApps.Administration.PowerShell:** 2.0.175+
- **Microsoft.PowerApps.PowerShell:** 1.0.34+
- **Az modules:** 10.0.0+ (for storage operations)

---

**🔗 Related Documentation:**
- [Microsoft Official API Documentation](https://docs.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/)
- [Power Platform Admin Center](https://admin.powerplatform.microsoft.com/)

---

**🌐 Available in:** **English** | [Español](../es/referencia-api.md)