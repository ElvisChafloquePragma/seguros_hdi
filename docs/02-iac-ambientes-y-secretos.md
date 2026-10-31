# Entregable 2: IaC, Gestión de Ambientes y Manejo de Secretos

> **Requisitos del PDF:**
> - *Implementar la infraestructura solicitada*
> - *¿Cómo garantizar consistencia entre `dev`, `staging` y `prod`?*
> - *¿Cómo validar los templates antes de desplegar?*
> - *¿Cómo manejar secretos sin exponerlos en el repositorio?*

---

## 1. Infraestructura Implementada en [`infra/template.yaml`](../infra/template.yaml)

Toda la arquitectura serverless solicitada (y los controles de seguridad de la **SFC**) está implementada en una **única plantilla autónoma de AWS SAM / CloudFormation** ([`infra/template.yaml`](../infra/template.yaml)) organizada en **6 secciones lógicas**:

| Sección en `template.yaml` | Recurso Lógico | Tipo de Recurso AWS | Propósito en la Arquitectura |
|---|---|---|---|
| **1. Seguridad y Secretos** | `AppKmsKey` + `AppKmsKeyAlias` | `AWS::KMS::Key` + `Alias` | Llave CMK administrada por el cliente con **rotación anual automática (`EnableKeyRotation: true`)** que cifra DynamoDB, S3 y Secrets Manager. |
| **1. Seguridad y Secretos** | `IntegrationSecret` | `AWS::SecretsManager::Secret` | Genera automáticamente la clave de integración (`GenerateSecretString`) cifrada con `AppKmsKey`, sin exponer valores en Git. |
| **2. Capa de Datos** | `ClaimsTable` | `AWS::DynamoDB::Table` | Tabla `PAY_PER_REQUEST` (On-Demand) con cifrado KMS, **Point-in-Time Recovery (`PITR`)** e índice secundario `StatusDateIndex`. En `prod` aplica `DeletionPolicy: Retain`. |
| **2. Capa de Datos** | `ReportsBucket` | `AWS::S3::Bucket` | Bucket para reportes PDF de siniestros con **cifrado KMS**, las 4 banderas de **`PublicAccessBlockConfiguration: true`** y ciclo de vida (`LifecycleConfiguration`). |
| **3. API y Autenticación** | `AgentsUserPool` + `AgentsUserPoolClient` | `AWS::Cognito::UserPool` | Directorio de agentes de seguros con política de contraseñas robusta y autenticación JWT para proteger la API. |
| **3. API y Autenticación** | `SiniestrosApi` | `AWS::Serverless::Api` | API Gateway REST con stage por ambiente (`/api/v1`), trazabilidad **AWS X-Ray (`TracingEnabled: true`)** y autorizador Cognito disponible. |
| **4. Funciones Lambda** | `ClaimsFunctionLogGroup` | `AWS::Logs::LogGroup` | Grupo de logs con retención parametrizada (`365 días` en `prod`) y **`DataProtectionPolicy` nativa** que enmascara datos sensibles con `*****`. |
| **4. Funciones Lambda** | `ClaimsFunction` | `AWS::Serverless::Function` | Lambda Node.js 22 (`arm64`) para `POST /claims`, `GET /claims/{id}`, `PATCH /claims/{id}` y `GET /health`. Incluye `AutoPublishAlias: live`, CodeDeploy y permisos IAM mínimos. |
| **4. Funciones Lambda** | `DocumentsFunction` | `AWS::Serverless::Function` | Lambda Node.js 22 (`arm64`) para `POST /documents/report` (guarda el reporte en S3 y devuelve URL prefirmada de 5 min). Incluye `AutoPublishAlias: live` y CodeDeploy. |
| **5. Frontend y CDN** | `FrontendBucket` + `FrontendBucketPolicy` | `AWS::S3::Bucket` + `BucketPolicy` | Bucket S3 100% privado que aloja el portal SPA y solo permite lectura desde CloudFront mediante firma criptográfica **OAC (`SigV4`)**. |
| **5. Frontend y CDN** | `CloudFrontOriginAccessControl` | `AWS::CloudFront::OriginAccessControl` | Identidad OAC (`sigv4` / `always`) para conectar CloudFront con el bucket privado S3. |
| **5. Frontend y CDN** | `FrontendWebACL` | `AWS::WAFv2::WebACL` | Firewall de aplicación web con `AWSManagedRulesCommonRuleSet` que se despliega automáticamente cuando `EnableWaf: true` (`prod`). |
| **5. Frontend y CDN** | `CloudFrontDistribution` | `AWS::CloudFront::Distribution` | CDN global con `redirect-to-https`, protocolo `TLSv1.2_2021`, soporte SPA (`403/404 -> /index.html`) y asociación opcional con WAFv2 y certificado ACM. |
| **6. Observabilidad** | `AlertsTopic` | `AWS::SNS::Topic` | Tópico SNS para enviar notificaciones inmediatas al equipo de operaciones cuando salta una alarma. |
| **6. Observabilidad** | `ClaimsFunctionErrorsAlarm`<br>`DocumentsFunctionErrorsAlarm`<br>`ApiGateway5xxAlarm` | `AWS::CloudWatch::Alarm` | 3 alarmas críticas que evalúan errores cada 60 segundos, notifican a `AlertsTopic` y disparan el **Rollback Automático en CodeDeploy**. |
| **6. Observabilidad** | `ObservabilityDashboard` | `AWS::CloudWatch::Dashboard` | Tablero operativo y de métricas **DORA** (`DeploymentFrequency`, `LeadTimeMinutes`, `ChangeFailureCount`, `MeanTimeToRestoreMinutes`). |

---

## 2. ¿Cómo garantizar consistencia entre `dev`, `staging` y `prod`?

Para eliminar la deriva de configuración (*Configuration Drift*) y las ediciones manuales (Problema #5), aplicamos **4 controles de Ingeniería DevOps**:

1. **Un Único Template Autónomo (`Single Source of Truth`):**
   No existen plantillas separadas (`template-dev.yaml`, `template-prod.yaml`). Los 3 ambientes nacen exactamente del mismo archivo [`infra/template.yaml`](../infra/template.yaml), garantizando que tengan la misma topología arquitectónica.
2. **Archivos de Parámetros Versionados en Git (`infra/params/*.json` y `infra/samconfig.toml`):**
   Las diferencias de capacidad, estrategia de despliegue y controles de producción se inyectan exclusivamente por parámetros controlados en Git:

   | Parámetro | [`dev.json`](../infra/params/dev.json) | [`staging.json`](../infra/params/staging.json) | [`prod.json`](../infra/params/prod.json) | Propósito de la Diferenciación |
   |---|---|---|---|---|
   | `Env` | `dev` | `staging` | `prod` | Aísla cada stack (`siniestros-dev`, `siniestros-staging`, `siniestros-prod`). |
   | `NodeRuntime` | `nodejs22.x` | `nodejs22.x` | `nodejs22.x` | Mantiene paridad exacta del motor de ejecución LTS. |
   | `LambdaMemorySize` | `256 MB` | `256 MB` | `512 MB` | Mayor capacidad de CPU/RAM en producción y ahorro en no-productivos. |
   | `LambdaTimeout` | `15 s` | `20 s` | `25 s` | Margen operativo gradual según el entorno. |
   | `DeploymentPreferenceType` | `AllAtOnce` | `Linear10PercentEvery1Minute` | `Canary10Percent5Minutes` | Agilidad en `dev`, validación progresiva en `staging` y seguridad Canary en `prod`. |
   | `EnableWaf` | `false` | `false` | `true` | Activa **AWS WAFv2** en producción sin incurrir en costos fijos en `dev`/`staging`. |
   | `LogRetentionDays` | `14 días` | `30 días` | `365 días` | Cumple el año de retención exigido por la **SFC** en producción. |

3. **Condiciones Declarativas (`Conditions` en `template.yaml`):**
   - `IsProd` (`!Equals [!Ref Env, prod]`): Activa `DeletionPolicy: Retain` y `UpdateReplacePolicy: Retain` en DynamoDB únicamente en producción.
   - `ShouldEnableWaf` (`!Equals [!Ref EnableWaf, 'true']`): Crea y vincula `FrontendWebACL` a CloudFront solo cuando corresponde.
   - `HasCustomCertificate`: Permite usar el certificado gratuito `*.cloudfront.net` o conectar un certificado personalizado de **AWS Certificate Manager (ACM)** sin tocar el código de la plantilla.
4. **Nomenclatura Dinámica libre de colisiones (`${ProjectName}-${Env}-*`):**
   Todos los nombres de recursos usan `!Sub "${ProjectName}-${Env}-..."`, lo que permite desplegar los 3 ambientes en la misma cuenta de AWS o clonar el stack con otro nombre en segundos.

---

## 3. ¿Cómo validar los templates antes de desplegar?

En la **Etapa 2 (`Stage 2: Validate Environment Config & IaC`)** y la **Etapa 4d (`Checkov`)** del [`Jenkinsfile`](../Jenkinsfile), ejecutamos **4 validaciones automáticas antes de permitir cualquier `sam deploy`**:

| Nivel de Validación | Herramienta / Comando | Archivo que Valida | Qué errores detecta y detiene antes de tocar AWS |
|---|---|---|---|
| **1. Sintaxis JSON** | `jq empty` (en [`scripts/validate-params.sh`](../scripts/validate-params.sh)) | `infra/params/{dev,staging,prod}.json` | Comas faltantes, llaves mal cerradas o JSON corrupto. |
| **2. Contrato de Esquema y Reglas SFC** | `check-jsonschema --schemafile infra/params/schema.json` + reglas en `validate-params.sh` | `infra/params/*.json` contra [`schema.json`](../infra/params/schema.json) | Detecta parámetros inventados (`additionalProperties: false`), memorias fuera de rango (`128–3008`), runtimes no permitidos o que alguien intente bajar `LogRetentionDays < 365` o apagar `EnableWaf` en `prod`. |
| **3. Sintaxis y Estructura CloudFormation/SAM** | `sam validate -t infra/template.yaml --region us-east-1` | [`infra/template.yaml`](../infra/template.yaml) | Verifica referencias intrínsecas (`!Ref`, `!GetAtt`, `!Sub`), tipos de recursos válidos y expansión de macros `AWS::Serverless-2016-10-31`. |
| **4. Seguridad Estática de IaC (Policy-as-Code)** | `checkov -f infra/template.yaml --framework cloudformation` | [`infra/template.yaml`](../infra/template.yaml) | Verifica que ningún cambio haya desactivado el cifrado KMS, el bloqueo de acceso público S3 (`PublicAccessBlockConfiguration`), el `PITR` de DynamoDB o el trazado X-Ray. |

---

## 4. ¿Cómo manejar secretos sin exponerlos en el repositorio? (100% desde DevOps)

Para resolver el **Problema #2** (*"Las credenciales de servicios externos están hardcodeadas en archivos de configuración"*) sin depender de los desarrolladores:

1. **Generación y Almacenamiento Cifrado en AWS Secrets Manager (`IntegrationSecret`):**
   En [`infra/template.yaml`](../infra/template.yaml) (Líneas 115–127), el recurso `IntegrationSecret` (`AWS::SecretsManager::Secret`) genera automáticamente el valor secreto directamente dentro de AWS mediante `GenerateSecretString` y lo cifra en reposo con nuestra llave **`AppKmsKey` (`AWS::KMS::Key`)**. El valor del secreto **jamás pasa por Git, ni por `params/*.json`, ni por Jenkins**.
2. **Inyección de Referencia (`ARN`) y Permisos IAM de Mínimo Privilegio por Función:**
   En lugar de escribir contraseñas en variables de entorno, `infra/template.yaml` inyecta únicamente la referencia al secreto (`INTEGRATION_SECRET_ARN: !Ref IntegrationSecret`) y otorga exclusivamente a `ClaimsFunction` los permisos `AWSSecretsManagerGetSecretValuePolicy` y `KMSDecryptPolicy` acotados a ese recurso (`DocumentsFunction` ni siquiera tiene permiso para leerlo).
3. **Credenciales Temporales de AWS (IAM Execution Roles):**
   Ni las Lambdas ni el servidor de Jenkins usan llaves estáticas (`AWS_ACCESS_KEY_ID` hardcodeadas); utilizan **Roles de IAM** que entregan credenciales temporales rotadas automáticamente por AWS STS.
4. **Bloqueo Preventivo en el Pipeline con Gitleaks (`Stage 4a`):**
   Si un desarrollador intenta subir por error una llave `AKIA...`, un token JWT o una contraseña en cualquier archivo del repositorio, **Gitleaks** (`gitleaks detect --redact`) lo detecta en la Etapa 4a y aborta el pipeline antes del despliegue.

---

## 5. Guion Corto para Sustentar el Entregable 2 en la Entrevista (30 segundos)
> *"Para el Entregable 2 implementamos toda la arquitectura en una única plantilla autónoma `infra/template.yaml`. Garantizamos la consistencia entre `dev`, `staging` y `prod` usando la misma plantilla base e inyectando únicamente las diferencias de capacidad y seguridad mediante `infra/samconfig.toml` y `infra/params/*.json`. Antes de desplegar, validamos los parámetros con `check-jsonschema` contra `schema.json`, la sintaxis con `sam validate` y la seguridad con `Checkov`. Finalmente, manejamos los secretos con **AWS Secrets Manager** cifrado con nuestra llave **KMS CMK (`AppKmsKey`)**, otorgando permisos IAM de mínimo privilegio por función y escaneando el repositorio con **Gitleaks** para que ningún secreto exista jamás en Git."*
