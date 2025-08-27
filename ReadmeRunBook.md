Runbook All in OneCómo usarlo (en VS Code Insiders, sesión Windows PowerShell 5.1):

Abre un terminal de Windows PowerShell (x64).


Ejecuta:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force



Lanza el runbook:
.\Runbook_TTT_AllInOne.ps1



En el menú, empieza por 0) Prereqs install/check.


Revisa/ajusta al principio los valores por defecto:


EnvironmentDisplayName = "CustomerExperienceDev"


TargetTenantId = "&lt;GUID_Tenant_Destino&gt;"


UserMappingCsvPath = "C:\migracion\usermapping.csv"


SecurityGroupId (opcional)




El script:


Guarda inventarios en .\runbook-output\inventory\


Registra estados de Prepare y Migrate en .\runbook-output\prepare-status.log y migration-status.log


En post-migración exporta flows-after.csv y te ofrece activar flujos deshabilitados (tras reautenticar conexiones)