# Referencia API de Migración Power Platform

> **🌐 Idioma:** [English](../en/api-reference.md) | **Español**

Referencia completa de todos los cmdlets de PowerShell utilizados en el proceso de migración tenant-a-tenant de Power Platform.

## 📚 Índice de Contenidos

- [Cmdlets de Autenticación](#cmdlets-de-autenticación)
- [Cmdlets de Solicitud de Migración](#cmdlets-de-solicitud-de-migración)
- [Gestión de Entornos](#gestión-de-entornos)
- [Mapeo de Usuarios](#mapeo-de-usuarios)
- [Monitoreo de Estado](#monitoreo-de-estado)
- [Funciones Helper](#funciones-helper)
- [Manejo de Errores](#manejo-de-errores)

---

## Cmdlets de Autenticación

### Add-PowerAppsAccount

Autentica a los servicios de Power Platform.

```powershell
Add-PowerAppsAccount -Endpoint prod [-TenantID <tenant-id>]
```

**Parámetros:**
- `Endpoint` - Endpoint del servicio (siempre usar 'prod' para producción)
- `TenantID` (Opcional) - ID específico del tenant para escenarios multi-tenant

**Ejemplo:**
```powershell
# Conectar a tenant origen
Add-PowerAppsAccount -Endpoint prod

# Conectar a tenant destino específico
Add-PowerAppsAccount -Endpoint prod -TenantID "12345678-1234-5678-9012-123456789012"
```

**Devuelve:** Objeto de sesión de autenticación

**Errores Comunes:**
- `AADSTS50020` - Cuenta de usuario no encontrada en el tenant
- `AADSTS65001` - Usuario no ha dado consentimiento a permisos de la app

---

## Cmdlets de Solicitud de Migración

### TenantToTenant-SubmitMigrationRequest

Inicia solicitud de migración desde el tenant origen.

```powershell
TenantToTenant-SubmitMigrationRequest -EnvironmentName <env-id> -TargetTenantID <tenant-id>
```

**Parámetros:**
- `EnvironmentName` - GUID del entorno origen
- `TargetTenantID` - GUID del tenant destino

**Ejemplo:**
```powershell
TenantToTenant-SubmitMigrationRequest `
    -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef" `
    -TargetTenantID "12345678-1234-5678-9012-123456789012"
```

**Devuelve:** Objeto de solicitud de migración con RequestID

**Prerrequisitos:**
- Debe estar autenticado al tenant origen
- El entorno debe ser tipo Production o Sandbox
- Usuario debe tener rol de Administrador de Entorno o Administrador de Power Platform

---

### TenantToTenant-ViewMigrationRequest

Visualiza solicitudes de migración pendientes en el tenant destino.

```powershell
TenantToTenant-ViewMigrationRequest -TenantID <tenant-id>
```

**Parámetros:**
- `TenantID` - ID del tenant destino

**Ejemplo:**
```powershell
$solicitudes = TenantToTenant-ViewMigrationRequest -TenantID "12345678-1234-5678-9012-123456789012"
$solicitudes | Format-List
```

**Devuelve:** Array de objetos de solicitud de migración pendientes

**Propiedades devueltas:**
- `MigrationId` - Identificador único de migración
- `SourceEnvironmentId` - GUID del entorno origen
- `SourceTenantId` - GUID del tenant origen
- `RequestedDate` - Cuándo se envió la solicitud
- `Status` - Estado actual de la solicitud

---

### TenantToTenant-ManageMigrationRequest

Aprueba o rechaza solicitud de migración en el tenant destino.

```powershell
TenantToTenant-ManageMigrationRequest -MigrationId <migration-id> [-Approve] [-Reject]
```

**Parámetros:**
- `MigrationId` - ID de migración de ViewMigrationRequest
- `Approve` - Switch para aprobar la solicitud
- `Reject` - Switch para rechazar la solicitud

**Ejemplo:**
```powershell
# Aprobar migración
TenantToTenant-ManageMigrationRequest -MigrationId "abc123" -Approve

# Rechazar migración
TenantToTenant-ManageMigrationRequest -MigrationId "abc123" -Reject
```

**Devuelve:** Objeto de solicitud de migración actualizado

---

## Gestión de Entornos

### Get-AdminPowerAppEnvironment

Obtiene entornos de Power Platform.

```powershell
Get-AdminPowerAppEnvironment [[-EnvironmentName] <env-id>]
```

**Parámetros:**
- `EnvironmentName` (Opcional) - ID específico del entorno

**Ejemplo:**
```powershell
# Obtener todos los entornos
$entornos = Get-AdminPowerAppEnvironment

# Obtener entorno específico
$env = Get-AdminPowerAppEnvironment -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef"

# Encontrar entorno por nombre de visualización
$env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq "Producción" }
```

**Devuelve:** Objeto(s) de entorno con propiedades:
- `EnvironmentName` - ID único del entorno (GUID)
- `DisplayName` - Nombre legible para humanos
- `EnvironmentType` - Production, Sandbox, Developer, etc.
- `Location` - Región geográfica
- `CreatedBy` - Información del creador

---

### Get-AdminFlow

Obtiene flujos de Power Automate del entorno.

```powershell
Get-AdminFlow -EnvironmentName <env-id>
```

**Parámetros:**
- `EnvironmentName` - ID del entorno

**Ejemplo:**
```powershell
$flujos = Get-AdminFlow -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef"
$flujos | Where-Object { $_.Enabled -eq $false } | Select-Object DisplayName, SolutionId
```

**Devuelve:** Array de objetos de flujo con propiedades:
- `FlowName` - Identificador único del flujo
- `DisplayName` - Nombre de visualización del flujo
- `Enabled` - Estado habilitado (boolean)
- `SolutionId` - ID de solución (null si no es consciente de solución)
- `CreatedTime` - Marca de tiempo de creación
- `LastModifiedTime` - Marca de tiempo de última modificación

---

## Mapeo de Usuarios

### TenantToTenant-UploadUserMappingFile

Sube archivo CSV de mapeo de usuarios al almacenamiento de migración.

```powershell
TenantToTenant-UploadUserMappingFile -EnvironmentName <env-id> -UserMappingFilePath <csv-path>
```

**Parámetros:**
- `EnvironmentName` - ID del entorno origen
- `UserMappingFilePath` - Ruta completa al archivo CSV

**Ejemplo:**
```powershell
TenantToTenant-UploadUserMappingFile `
    -EnvironmentName "a1b2c3d4-e5f6-7890-1234-567890abcdef" `
    -UserMappingFilePath "C:\Migracion\mapeo-usuarios.csv"
```

**Formato CSV Requerido:**
```csv
SourceUpn,TargetUpn
usuario1@origen.com,usuario1@destino.com
usuario2@origen.com,usuario2@destino.com
```

**Devuelve:** Objeto de confirmación de carga

---

## Ejecución de Migración

### TenantToTenant-PrepareMigration

Prepara el entorno para migración.

```powershell
TenantToTenant-PrepareMigration -MigrationId <migration-id> -TargetTenantId <tenant-id>
```

**Parámetros:**
- `MigrationId` - ID de migración del paso de aprobación
- `TargetTenantId` - ID del tenant destino

**Ejemplo:**
```powershell
TenantToTenant-PrepareMigration `
    -MigrationId "abc123def456" `
    -TargetTenantId "12345678-1234-5678-9012-123456789012"
```

**Devuelve:** Objeto de trabajo de preparación

**Duración:** Típicamente 10-30 minutos dependiendo del tamaño del entorno

---

### TenantToTenant-MigratePowerAppEnvironment

Ejecuta la migración real.

```powershell
TenantToTenant-MigratePowerAppEnvironment -MigrationId <migration-id> -TargetTenantId <tenant-id> [-SecurityGroupId <group-id>]
```

**Parámetros:**
- `MigrationId` - ID de migración
- `TargetTenantId` - ID del tenant destino
- `SecurityGroupId` (Opcional) - Grupo de seguridad para acceso al entorno

**Ejemplo:**
```powershell
# Migración básica
TenantToTenant-MigratePowerAppEnvironment `
    -MigrationId "abc123def456" `
    -TargetTenantId "12345678-1234-5678-9012-123456789012"

# Con grupo de seguridad
TenantToTenant-MigratePowerAppEnvironment `
    -MigrationId "abc123def456" `
    -TargetTenantId "12345678-1234-5678-9012-123456789012" `
    -SecurityGroupId "sg-98765432-1234-5678-9012-123456789012"
```

**Devuelve:** Objeto de trabajo de migración

**Duración:** 1-8 horas dependiendo de la complejidad del entorno

---

## Monitoreo de Estado

### TenantToTenant-GetMigrationStatus

Monitorea el progreso de migración.

```powershell
TenantToTenant-GetMigrationStatus -MigrationId <migration-id>
```

**Parámetros:**
- `MigrationId` - ID de migración a monitorear

**Ejemplo:**
```powershell
$estado = TenantToTenant-GetMigrationStatus -MigrationId "abc123def456"
Write-Host "Estado: $($estado.Status) - Progreso: $($estado.Progress)%"
```

**Devuelve:** Objeto de estado con propiedades:
- `Status` - Fase actual (NotStarted, Running, InProgress, Succeeded, Failed)
- `Progress` - Porcentaje completo (0-100)
- `StartTime` - Marca de tiempo de inicio de migración
- `EstimatedEndTime` - Tiempo estimado de finalización
- `ErrorDetails` - Información de error si falló

**Valores de Estado:**
- `NotStarted` - Migración en cola pero no iniciada
- `Running` / `InProgress` - Migración procesando activamente
- `Succeeded` - Migración completada exitosamente
- `Failed` - Migración encontró errores
- `Queued` - Esperando recursos

---

## Funciones Helper (Config.ps1)

### Test-ConfigurationValid

Valida parámetros de configuración.

```powershell
Test-ConfigurationValid
```

**Valida:**
- `$Global:TargetTenantId` está configurado
- `$Global:EnvironmentDisplayName` está configurado
- Las rutas de archivo requeridas existen

**Devuelve:** Boolean (verdadero/falso)

**Lanza:** Errores de validación de configuración

---

### Get-EnvironmentId

Resuelve nombre de visualización del entorno a GUID.

```powershell
Get-EnvironmentId -DisplayName <nombre-entorno>
```

**Parámetros:**
- `DisplayName` - Nombre de visualización del entorno

**Ejemplo:**
```powershell
$envId = Get-EnvironmentId -DisplayName "CRM Producción"
```

**Devuelve:** String GUID del entorno

---

### Write-MigrationLog

Función de logging estandarizada.

```powershell
Write-MigrationLog -Message <mensaje> [-Level <nivel>]
```

**Parámetros:**
- `Message` - Texto del mensaje de log
- `Level` - Nivel de log (Info, Warning, Error, Success)

**Ejemplo:**
```powershell
Write-MigrationLog "Migración iniciada" "Info"
Write-MigrationLog "Conexión falló" "Error"
Write-MigrationLog "Fase completada" "Success"
```

**Salida:** Consola + archivo de log

---

## Manejo de Errores

### Códigos de Error Comunes

| Código de Error | Descripción | Solución |
|----------------|-------------|----------|
| `EnvironmentNotFound` | El entorno no existe | Verificar nombre del entorno y permisos |
| `InvalidEnvironmentType` | Tipo de entorno no soportado | Usar solo Production o Sandbox |
| `UserMappingInvalid` | Formato CSV incorrecto | Verificar estructura y codificación del CSV |
| `MigrationTimeout` | La migración excedió el límite de tiempo | Verificar tamaño del entorno y reintentar |
| `InsufficientPermissions` | Usuario carece de permisos requeridos | Verificar roles de administrador |
| `TenantNotFound` | El tenant destino no existe | Verificar ID del tenant |

### Patrones de Recuperación de Errores

**Errores de Autenticación:**
```powershell
# Limpiar sesión y reconectar
Clear-Variable -Name * -Scope Global -ErrorAction SilentlyContinue
Add-PowerAppsAccount -Endpoint prod
```

**Errores de Timeout:**
```powershell
# Verificar estado y reanudar
$estado = TenantToTenant-GetMigrationStatus -MigrationId $migrationId
if ($estado.Status -eq "Failed") {
    # Revisar detalles del error y reintentar preparación
}
```

**Errores de Permisos:**
```powershell
# Verificar asignaciones de rol
Get-AdminPowerAppRoleAssignment -EnvironmentName $envId
```

---

## Límites de Velocidad y Throttling

- **Llamadas API:** 600 solicitudes por hora por usuario
- **Migraciones concurrentes:** 1 por par de tenants
- **Intervalos de reintento:** 30 segundos mínimo entre verificaciones de estado

## Versiones SDK

- **Microsoft.PowerApps.Administration.PowerShell:** 2.0.175+
- **Microsoft.PowerApps.PowerShell:** 1.0.34+
- **Módulos Az:** 10.0.0+ (para operaciones de almacenamiento)

---

**🔗 Documentación Relacionada:**
- [Documentación Oficial API de Microsoft](https://docs.microsoft.com/es-es/powershell/module/microsoft.powerapps.administration.powershell/)
- [Centro de Administración de Power Platform](https://admin.powerplatform.microsoft.com/)

---

**🌐 Disponible en:** [English](../en/api-reference.md) | **Español**