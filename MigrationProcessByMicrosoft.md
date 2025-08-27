Sigue estos pasos de forma secuencial para mover un entorno entre tenants. Reemplaza las llaves `{...}` por los valores apropiados.

## Requisitos previos

- Módulos PowerShell instalados: `Microsoft.PowerApps.Administration.PowerShell` y `Az`.
- Credenciales de administrador del tenant origen y destino.
- Archivo de mapeo de usuarios (`usermapping.csv`) preparado localmente.

## Resumen de responsabilidades

- **Admin Origen**: Ejecuta la mayoría de los pasos (envío de solicitud, generación de SAS, subida del mapping, preparación y migración).
- **Admin Destino**: Visualiza y aprueba la solicitud; puede necesitar ejecutar comandos en su contexto cuando se indica.

## Pasos (ordenados)

1. Instalar módulos PowerShell

```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell
Update-Module -Name Microsoft.PowerApps.Administration.PowerShell
Install-Module -Name Az -Repository PSGallery -Force
```

2. Iniciar sesión (contexto Origen)

```powershell
Add-PowerAppsAccount -Endpoint prod
```

3. Enviar la solicitud de migración (Origen)

```powershell
TenantToTenant-SubmitMigrationRequest –EnvironmentName {EnvironmentId} -TargetTenantID {TenantID}
```

4. Iniciar sesión (contexto Destino) y ver la solicitud (Destino)

```powershell
Add-PowerAppsAccount -Endpoint prod
TenantToTenant-ViewMigrationRequest -TenantID {TenantID}
```

5. Aprobar o rechazar la solicitud (Destino)

```powershell
TenantToTenant-ManageMigrationRequest -RequestId {RequestId}
# Se solicitará: "Enter approval status ... (0 for Rejected, 1 for Approved): {0/1}"
```

6. Generar SAS URI para el storage de recursos (Origen)

```powershell
GenerateResourceStorage-PowerAppEnvironment –EnvironmentName {EnvironmentId}
# Copia el SAS URI devuelto y guárdalo en la variable $SASUri
```

7. Subir archivo de mapeo de usuarios a Blob Storage (Origen)

Reemplaza `{SASUri}` por el SAS obtenido en el paso anterior.

```powershell
$SASUri = '{SASUriDesdePasoAnterior}'
$Uri = [System.Uri] $SASUri
$storageAccountName = $Uri.DnsSafeHost.Split(".")[0]
$container = $Uri.LocalPath.TrimStart('/')
$sasToken = $Uri.Query

$fileToUpload = 'C:\filelocation\usermapping.csv'

$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken

Set-AzStorageBlobContent -File $fileToUpload -Container $container -Context $storageContext -Force
```

8. Preparar entorno para migración (Origen)

```powershell
TenantToTenant-PrepareMigration -EnvironmentName {EnvironmentId} -TargetTenantId {TargetTenantId} -ReadOnlyUserMappingFileContainerUri {SasUri}
```

9. Obtener estado de la migración (Origen)

```powershell
TenantToTenant-GetStatus -EnvironmentName {EnvironmentId}
```

10. Si hay fallos en el archivo de mapeo: descargar el reporte de fallos, corregir y re-subir

Ejemplo para descargar `usermapping.csv` del blob (ajusta según sea necesario):

```powershell
$sasUri = '{SasUriDesdePasoAnterior}'
$destinationPath = 'C:\Downloads\Failed\'

# Separar URL y token
$url, $sasToken = $sasUri -split '\?', 2

# Extraer container y storage account
$containerName = $url.Split('/')[3]
$storageAccountName = $url.Split('/')[2].Split('.')[0]

$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken

Get-AzStorageBlobContent -Blob "usermapping.csv" -Container $containerName -Destination $destinationPath -Context $storageContext
```

- Corregir el CSV y volver a subirlo (volver al paso 7 o usar el mismo SAS).

11. Migrar el entorno (Origen)

```powershell
TenantToTenant-MigratePowerAppEnvironment -EnvironmentName {EnvironmentId} -TargetTenantId {TargetTenantId}
```

## Notas importantes

- Ejecuta los pasos en orden: algunos requieren credenciales/contextos distintos (origen vs destino).
- Si `TenantToTenant-GetStatus` muestra fallos por user mapping, corrige el CSV, vuelve a subir y repite la preparación/migración.
- Puedes usar el mismo SAS URI proporcionado o generar uno nuevo.
- Artículo de referencia:
 	- <https://learn.microsoft.com/en-us/power-platform/admin/move-environment-tenant>
