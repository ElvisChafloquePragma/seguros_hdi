# Guía Maestra Línea por Línea de `infra/template.yaml` (577 Líneas)

Este documento explica **a punta de detalle** cada bloque, propiedad y función de [`infra/template.yaml`](../infra/template.yaml) para que domines el archivo al 100% durante la sustentación y la prueba práctica en vivo.

---

## 0. Diccionario Rápido de Funciones de CloudFormation (Para no dudar en vivo)

Antes de leer los bloques, recuerda estas **5 funciones intrínsecas** que aparecen en todo el archivo:

| Función en YAML | Qué significa | Ejemplo real en nuestro `template.yaml` |
|---|---|---|
| **`!Ref Nombre`** | Devuelve el **valor** de un Parámetro o el **ID/Nombre físico** de un Recurso. | `!Ref Env` devuelve `"dev"`.<br>`!Ref ClaimsTable` devuelve `"siniestros-dev-claims"`. |
| **`!GetAtt Recurso.Atributo`** | Obtiene un **atributo especial** de un recurso (casi siempre su `Arn` o su `DomainName`). | `!GetAtt AppKmsKey.Arn` devuelve el ARN completo `arn:aws:kms:us-east-1:...` |
| **`!Sub 'texto-${Variable}'`** | Sustituye variables dentro de un texto (como `${VAR}` en Bash). Incluye pseudo-parámetros de AWS como `${AWS::AccountId}`, `${AWS::Region}` y `${AWS::StackName}`. | `!Sub '${ProjectName}-${Env}-claims'` se convierte en `"siniestros-dev-claims"`. |
| **`!Equals [A, B]`** | Compara si `A` es igual a `B` (`true` o `false`). Se usa en `Conditions`. | `!Equals [!Ref Env, 'prod']` es verdadero solo cuando desplegamos producción. |
| **`!If [Condicion, ValorSiTrue, ValorSiFalse]`** | Funciona como un `if / else` para cambiar una propiedad según el ambiente. | `DeletionPolicy: !If [IsProd, Retain, Delete]` protege la tabla en `prod` y permite borrarla en `dev`. |

---

## 1. Mapa Estructural de las 577 Líneas de `infra/template.yaml`

| Rango de Líneas | Sección Principal | Qué contiene |
|---|---|---|
| **Líneas 1–8** | **Cabecera (`Header & Transform`)** | Versión de CloudFormation y activación del motor **AWS SAM (`AWS::Serverless-2016-10-31`)**. |
| **Líneas 9–59** | **`Parameters` (9 Parámetros)** | Variables de entrada que diferencian `dev`, `staging` y `prod` sin tocar el código de la plantilla. |
| **Líneas 60–64** | **`Conditions` (3 Condiciones)** | Interruptores lógicos (`IsProd`, `ShouldEnableWaf`, `HasCustomCertificate`). |
| **Líneas 65–84** | **`Globals` (Configuración Común Lambda)** | Propiedades heredadas automáticamente por todas las funciones Lambda (Node 22, `arm64`, X-Ray, Logs JSON y variables de entorno). |
| **Líneas 85–126** | **`Resources` — Bloque 1: Seguridad SFC** | `AppKmsKey` (Llave KMS CMK con rotación anual) + `IntegrationSecret` (Secrets Manager). |
| **Líneas 127–167** | **`Resources` — Bloque 2: Capa de Datos** | `ClaimsTable` (DynamoDB On-Demand + PITR + KMS) + `ReportsBucket` (S3 privado cifrado con KMS). |
| **Líneas 168–194** | **`Resources` — Bloque 3: API y Cognito** | `AgentsUserPool` (Cognito) + `SiniestrosApi` (API Gateway REST con X-Ray y CORS). |
| **Líneas 195–303** | **`Resources` — Bloque 4: Cómputo Lambda** | `ClaimsFunctionLogGroup` (con `DataProtectionPolicy` PII) + `ClaimsFunction` + `DocumentsFunction` (ambas con CodeDeploy Canary). |
| **Líneas 304–428** | **`Resources` — Bloque 5: Frontend y Perímetro** | `FrontendBucket` + `CloudFrontOriginAccessControl` (OAC) + `FrontendWebACL` (WAFv2) + `CloudFrontDistribution` + `FrontendBucketPolicy`. |
| **Líneas 429–558** | **`Resources` — Bloque 6: Observabilidad** | `AlertsTopic` (SNS) + 3 `AWS::CloudWatch::Alarm` (conectadas al Auto-Rollback) + `ObservabilityDashboard` (Operaciones + DORA). |
| **Líneas 559–577** | **`Outputs` (6 Salidas)** | URLs e IDs exportados al terminar el despliegue (usados por `deploy-frontend.sh` y `smoke-test.sh`). |

---

## 2. Explicación Detallada Sección por Sección

### Parte A: Cabecera y Transform (Líneas 1–8)
```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
```
- **`AWSTemplateFormatVersion: '2010-09-09'`**: Es la cabecera estándar obligatoria de todo template de CloudFormation.
- **`Transform: AWS::Serverless-2016-10-31`**: **¡Línea clave!** Le dice a CloudFormation que este archivo usa **AWS SAM (Serverless Application Model)**. Gracias a esta línea podemos usar recursos abreviados como `AWS::Serverless::Function` y `AWS::Serverless::Api`, y cuando desplegamos, AWS los expande automáticamente en roles IAM, permisos de invocación, alias `:live` y grupos de despliegue de **CodeDeploy** (ahorrándonos más de 400 líneas de YAML repetitivo).

---

### Parte B: `Parameters` — Los 9 Parámetros de Entrada (Líneas 9–59)

Son las "perillas" que [`infra/samconfig.toml`](../infra/samconfig.toml) cambia según si despliegas `dev`, `staging` o `prod`:

| Parámetro | Líneas | Restricción (`AllowedValues` / Rango) | Para qué sirve exactamente |
|---|---|---|---|
| **`Env`** | L10–14 | `[dev, staging, prod]` | Define el ambiente actual; se usa en todos los nombres de recursos y activa la condición `IsProd`. |
| **`ProjectName`** | L15–18 | Default: `siniestros` | Prefijo global. **Truco para entrevista:** si te piden recrear otro stack paralelo en vivo sin borrar el actual, solo cambias `ProjectName=siniestros2` y cero nombres chocan. |
| **`NodeRuntime`** | L19–23 | `[nodejs22.x, nodejs24.x]` | Motor Node.js LTS actualizado (corrige el Node 20 próximo a EOL del enunciado). |
| **`LambdaMemorySize`** | L24–29 | `128` a `3008` MB | RAM de las Lambdas (`256 MB` en `dev`/`staging`, `512 MB` en `prod`). |
| **`LambdaTimeout`** | L30–35 | `5` a `120` seg | Tiempo máximo antes de cortar una ejecución colgada (`15s` en `dev`, `25s` en `prod`). |
| **`DeploymentPreferenceType`** | L36–44 | `AllAtOnce`, `Linear10PercentEvery1Minute`, `Canary10Percent5Minutes`, `Canary10Percent10Minutes` | Define cómo **AWS CodeDeploy** mueve el tráfico hacia la nueva versión de las Lambdas. |
| **`EnableWaf`** | L45–49 | `['true', 'false']` | Enciende el firewall **AWS WAFv2** en `prod` (`true`) y lo apaga en `dev`/`staging` (`false`) para no gastar \$5 USD fijos en ambientes de prueba. |
| **`LogRetentionDays`** | L50–54 | `[7, 14, 30, 90, 180, 365]` | Días que CloudWatch guarda los logs (`14` en `dev`, `30` en `staging`, `365` en `prod` por auditoría SFC). |
| **`CustomDomainCertificateArn`** | L55–58 | Default: `''` (vacío) | Si la empresa tiene un dominio propio con certificado en **ACM**, pega aquí su ARN; si está vacío, usa gratis el certificado HTTPS `*.cloudfront.net`. |

---

### Parte C: `Conditions` — Decisiones Inteligentes por Ambiente (Líneas 60–64)
```yaml
Conditions:
  IsProd: !Equals [!Ref Env, 'prod']
  ShouldEnableWaf: !Equals [!Ref EnableWaf, 'true']
  HasCustomCertificate: !Not [!Equals [!Ref CustomDomainCertificateArn, '']]
```
1. **`IsProd`**: Vale `true` solo si `Env == 'prod'`. La usamos en DynamoDB (L132–133) para que en producción la tabla tenga `DeletionPolicy: Retain` (nunca se borre aunque alguien borre el stack), mientras que en `dev` tenga `Delete` (para limpiar el laboratorio sin dejar basura ni costos).
2. **`ShouldEnableWaf`**: Si `EnableWaf == 'true'`, crea el recurso `FrontendWebACL` (L334) y lo conecta a CloudFront (L367). Si es `'false'`, ni siquiera crea el WAF.
3. **`HasCustomCertificate`**: Si `CustomDomainCertificateArn` NO está vacío, configura el certificado ACM con `TLSv1.2_2021` en CloudFront; si está vacío, usa `CloudFrontDefaultCertificate: true` (L368–373).

---

### Parte D: `Globals` — Configuración Heredada por Todas las Lambdas (Líneas 65–84)
En SAM, todo lo que pongas bajo `Globals.Function` se aplica automáticamente a **`ClaimsFunction`** y a **`DocumentsFunction`** (evitando duplicar código):
- **`Architectures: [arm64]` (L68–69)**: Procesadores **AWS Graviton2** (20% más baratos y ~19% mejor rendimiento que `x86_64`, tal como indica el PDF).
- **`Tracing: Active` (L72)**: Activa **AWS X-Ray** en todas las Lambdas para trazabilidad end-to-end.
- **`LoggingConfig: LogFormat: JSON` (L73–76)**: **Control 100% DevOps.** Fuerza desde la infraestructura de AWS que cualquier `console.log` de las Lambdas se guarde estructurado en JSON con `timestamp`, `level` y `requestId`.
- **`Environment.Variables` (L77–83)**: Inyecta dinámicamente en las Lambdas el nombre real de la tabla (`CLAIMS_TABLE_NAME`), del bucket de reportes (`REPORTS_BUCKET_NAME`), el ARN del secreto (`INTEGRATION_SECRET_ARN`) y el ARN de la llave KMS (`KMS_KEY_ARN`). **Cero nombres o secretos hardcodeados.**

---

### Parte E: `Resources` — Los 6 Bloques de Infraestructura (Líneas 85–558)

#### Bloque 1: Seguridad SFC — `AppKmsKey` e `IntegrationSecret` (Líneas 89–126)
1. **`AppKmsKey` (`AWS::KMS::Key`, L89–113)**:
   - Crea una llave criptográfica administrada por el cliente (**CMK**) con **`EnableKeyRotation: true`** (AWS rota el material criptográfico automáticamente cada 365 días sin romper datos antiguos).
   - `PendingWindowInDays: 7`: Si se elimina el stack de laboratorio, programa la destrucción de la llave en el mínimo permitido por AWS (7 días).
   - `KeyPolicy`: Da administración al `root` de la cuenta (lo cual habilita que las políticas IAM de las Lambdas funcionen) y permite a `cloudwatch.amazonaws.com` y `sns.amazonaws.com` usar la llave para alertas.
2. **`IntegrationSecret` (`AWS::SecretsManager::Secret`, L115–126)**:
   - Resuelve el **Problema #2 (credenciales hardcodeadas)**.
   - Usa `GenerateSecretString` para inventar automáticamente en AWS un `apiKey` aleatorio de 24 caracteres dentro del JSON `{"provider":"AsistenciaVehicularHDI","apiKey":"..."}` y lo cifra con `KmsKeyId: !Ref AppKmsKey`. **El valor secreto jamás toca Git ni tu laptop.**

---

#### Bloque 2: Capa de Datos — `ClaimsTable` y `ReportsBucket` (Líneas 130–167)
1. **`ClaimsTable` (`AWS::DynamoDB::Table`, L130–148)**:
   - `BillingMode: PAY_PER_REQUEST`: Modo **On-Demand** (pago por petición, \$0 si no hay tráfico, cero aprovisionamiento manual de RCUs/WCUs).
   - `KeySchema`: Llave primaria de partición (`HASH`) llamada `claimId` de tipo String (`S`).
   - `PointInTimeRecoverySpecification: PointInTimeRecoveryEnabled: true`: Habilita backups continuos al segundo durante los últimos 35 días (**requisito de resiliencia SFC**).
   - `SSESpecification`: Cifra toda la tabla en reposo usando nuestra llave KMS (`KMSMasterKeyId: !Ref AppKmsKey`).
2. **`ReportsBucket` (`AWS::S3::Bucket`, L150–173)**:
   - Guarda los reportes PDF generados por la Lambda `documents`.
   - Tiene **versionamiento activo** (`VersioningConfiguration: Enabled`), **cifrado KMS** (`SSEAlgorithm: aws:kms` + `BucketKeyEnabled: true`, que reduce en 99% las llamadas y costos hacia KMS) y las **4 banderas de bloqueo de acceso público en `true`** (`PublicAccessBlockConfiguration`).
   - **Plus FinOps y Cumplimiento SFC (`LifecycleConfiguration`, L164–173)**: Mueve los reportes a los 90 días a `STANDARD_IA` y al año (365 días) a `GLACIER_IR`, cumpliendo la custodia legal probatoria de siniestros de 5 años con un ahorro del 68% en almacenamiento.

---

#### Bloque 3: API, Acceso Forense y Autenticación — `AgentsUserPool`, `ApiAccessLogGroup` y `SiniestrosApi` (Líneas 177–205)
1. **`AgentsUserPool` (`AWS::Cognito::UserPool`, L177–185)**:
   - Directorio de usuarios en **Amazon Cognito** (capa gratuita hasta 50,000 usuarios activos/mes) donde los agentes inician sesión con su correo.
2. **`ApiAccessLogGroup` (`AWS::Logs::LogGroup`, L183–187) [Plus Auditoría Forense SFC]**:
   - Grupo de logs dedicado `/aws/apigateway/${ProjectName}-${Env}-api-access` con retención configurable.
3. **`SiniestrosApi` (`AWS::Serverless::Api`, L188–205)**:
   - Crea el **API Gateway REST** con `StageName: !Ref Env` (`/dev`, `/staging` o `/prod`).
   - **`AccessLogSetting` (L194–196) [Plus Auditoría Forense SFC]**: Registra en JSON en CloudWatch cada IP de origen, usuario autenticado de Cognito, latencia, método HTTP y RequestId (Circular 007 SFC).
   - `TracingEnabled: true`: Conecta el API Gateway con **AWS X-Ray**.
   - `Cors`: Permite llamadas desde el navegador (`GET, POST, PATCH, OPTIONS`).
   - `Auth.Authorizers.CognitoAgentAuthorizer`: Registra el User Pool de Cognito como validador nativo de tokens JWT en el API Gateway.

---

#### Bloque 4: Cómputo — `ClaimsFunctionLogGroup`, `ClaimsFunction` y `DocumentsFunction` (Líneas 198–303)
1. **`ClaimsFunctionLogGroup` (`AWS::Logs::LogGroup`, L198–222)**:
   - Crea explícitamente el grupo de logs `/aws/lambda/${ProjectName}-${Env}-claims` con retención `RetentionInDays: !Ref LogRetentionDays`.
   - **`DataProtectionPolicy` (L203–221)**: **Joya DevOps para la entrevista.** Aplica una política nativa de AWS CloudWatch Logs con dos operaciones (`Audit` y `Deidentify -> MaskConfig: {}`) sobre identificadores gestionados por AWS (`EmailAddress` y `AwsSecretKey`). Si al backend se le escapa un correo o llave secreta en un log, CloudWatch lo reemplaza automáticamente por `*****` antes de guardarlo.
2. **`ClaimsFunction` (`AWS::Serverless::Function`, L223–269)**:
   - `DependsOn: ClaimsFunctionLogGroup`: Asegura que el LogGroup con protección PII exista antes de crear la Lambda.
   - `CodeUri: ../backend/claims` y `Handler: index.handler`: Toma el archivo `backend/claims/index.mjs` y ejecuta su función `handler`.
   - **`AutoPublishAlias: live` + `DeploymentPreference` (L231–236)**: Resuelve el **Problema #6 (Rollback)**. Publica una versión nueva en cada cambio y le entrega el control del alias `:live` a **AWS CodeDeploy**, vigilando `ClaimsFunctionErrorsAlarm` y `ApiGateway5xxAlarm`.
   - **`Policies` (L237–250 — Mínimo Privilegio IAM)**:
     - `DynamoDBCrudPolicy` **solo** sobre `ClaimsTable`.
     - `AWSSecretsManagerGetSecretValuePolicy` **solo** sobre `IntegrationSecret`.
     - Permisos KMS (`Decrypt`, `Encrypt`, `GenerateDataKey*`) **solo** sobre `AppKmsKey`.
   - **`Events` (L250–269)**: Conecta los 3 endpoints exactos del PDF en `SiniestrosApi`:
     - `POST /api/v1/claims`
     - `GET /api/v1/claims/{id}`
     - `PATCH /api/v1/claims/{id}`
3. **`DocumentsFunction` (`AWS::Serverless::Function`, L270–303)**:
   - Toma `../backend/documents` (`index.handler`).
   - También tiene `AutoPublishAlias: live` + `DeploymentPreference` vigilando `DocumentsFunctionErrorsAlarm` y `ApiGateway5xxAlarm`.
   - **Nota la diferencia de Mínimo Privilegio IAM en `Policies` (L283–296)**:
     - A diferencia de `claims`, `documents` **NO tiene permiso de escritura en DynamoDB** (`DynamoDBReadPolicy` — solo lectura) y **NO tiene acceso a `Secrets Manager`**, pero **SÍ tiene `S3CrudPolicy`** sobre `ReportsBucket`.
   - **`Events`**: Conecta el 4to endpoint del PDF: `POST /api/v1/documents/report`.

---

#### Bloque 5: Frontend SPA, CloudFront OAC y WAFv2 (Líneas 307–428)
1. **`FrontendBucket` (`AWS::S3::Bucket`, L307–322)**:
   - Bucket S3 100% privado (`PublicAccessBlockConfiguration` todo en `true`) con cifrado `AES256` (requerido para compatibilidad directa y sin sobrecosto con orígenes S3 de CloudFront).
2. **`CloudFrontOriginAccessControl` (`OAC`, L323–330)**:
   - Es el estándar moderno de AWS (reemplazo del antiguo OAI). Hace que CloudFront firme cada lectura hacia S3 con **`sigv4`** (`SigningBehavior: always`).
3. **`FrontendWebACL` (`AWS::WAFv2::WebACL`, L332–356)**:
   - Tiene `Condition: ShouldEnableWaf` (solo nace si `EnableWaf == 'true'`).
   - Activa el grupo de reglas administradas por AWS **`AWSManagedRulesCommonRuleSet`** (protege contra SQLi, XSS y OWASP Top 10).
4. **`CloudFrontDistribution` (`AWS::CloudFront::Distribution`, L358–411)**:
   - **¡Diseño de arquitectura muy limpio!** Configura **2 orígenes (`Origins`) bajo el mismo dominio HTTPS de CloudFront**:
     1. **`S3FrontendOrigin` (`DefaultCacheBehavior`)**: Sirve el portal React/SPA (`index.html` y estáticos) con caché optimizada (`CachingOptimized`), redirige HTTP a HTTPS (`redirect-to-https`) y aplica **`ResponseHeadersPolicyId: 67f7725c-6f97-4210-82d7-5512b31e9d03` [Plus Ciberseguridad]**, forzando automáticamente HSTS, X-Frame-Options: DENY y nosniff para obtener una calificación **A+** en auditorías OWASP.
     2. **`ApiGatewayOrigin` (`PathPattern: '/api/*'`)**: Enruta todas las llamadas a `/api/v1/...` directamente hacia `SiniestrosApi` con caché desactivada (`CachingDisabled` = `4135ea2d-...`) y reenviando headers/query strings (`AllViewerExceptHostHeader` = `b689b0a8-...`). **¿Ventaja?** El frontend llama a `/api/v1/claims` en su mismo dominio HTTPS sin problemas de CORS ni exponer URLs internas.
   - `CustomErrorResponses` (L404–411): Convierte `403`/`404` de S3 en `/index.html` (`200`) para que las rutas del SPA funcionen al recargar la página.
5. **`FrontendBucketPolicy` (`AWS::S3::BucketPolicy`, L412–428)**:
   - Autoriza `s3:GetObject` sobre `FrontendBucket` **única y exclusivamente** al servicio `cloudfront.amazonaws.com` cuando el `AWS:SourceArn` coincide exactamente con nuestra distribución `CloudFrontDistribution`. Nadie más en Internet puede leer el bucket.

---

#### Bloque 6: Observabilidad — SNS, 3 Alarmas de Auto-Rollback y Dashboard DORA (Líneas 432–558)
1. **`AlertsTopic` (`AWS::SNS::Topic`, L432–435)**:
   - Canal de notificaciones al que se suscriben correos, Slack o PagerDuty del equipo SRE/DevOps.
2. **Las 3 Alarmas Críticas (`AWS::CloudWatch::Alarm`, L437–495)**:
   - **`ClaimsFunctionErrorsAlarm`**: Vigila `Errors` en `ClaimsFunction` cada `60` seg. Si `Sum >= 1`, pasa a `ALARM`, avisa a `AlertsTopic` y **dispara el Auto-Rollback en CodeDeploy**.
   - **`DocumentsFunctionErrorsAlarm`**: Igual para `DocumentsFunction` (`Sum >= 1` en `60` seg).
   - **`ApiGateway5xxAlarm`**: Vigila `5XXError` en `SiniestrosApi`. Si `Sum >= 2` en `60` seg, avisa a `AlertsTopic` y **dispara el Auto-Rollback en ambas Lambdas**.
   - *Detalle clave:* Todas tienen `TreatMissingData: notBreaching` (L452, L471, L492). Esto significa que si en la madrugada no hay tráfico (0 peticiones), la alarma se mantiene en verde (`OK`) en vez de dar falsas alarmas por falta de datos.
3. **`ObservabilityDashboard` (`AWS::CloudWatch::Dashboard`, L496–558)**:
   - Construye en JSON un tablero con **3 widgets**:
     - Arriba izquierda: Tráfico total (`Count`) vs errores `5XXError` del API Gateway.
     - Arriba derecha: `Invocations` vs `Errors` de las 2 Lambdas (`claims` y `documents`).
     - Abajo ancho completo: Las **4 métricas DORA** (`DeploymentFrequency`, `LeadTimeMinutes`, `ChangeFailureCount`, `MeanTimeToRestoreMinutes`) que alimenta nuestro script `scripts/dora-metrics.sh`.

---

### Parte F: `Outputs` — Las 6 Salidas del Stack (Líneas 559–577)
Al terminar `sam deploy`, CloudFormation imprime y guarda estos 6 valores:
- `ApiEndpointUrl`: URL directa del API Gateway (`https://...execute-api.us-east-1.amazonaws.com/dev/api/v1`).
- `CloudFrontUrl`: URL pública HTTPS del portal completo (`https://d12345.cloudfront.net`).
- `CloudFrontDistributionId` y `FrontendBucketName`: Leídos automáticamente por [`scripts/deploy-frontend.sh`](../scripts/deploy-frontend.sh) para subir el SPA e invalidar la caché sin hardcodear nada.
- `ReportsBucketName` y `ClaimsTableName`: Referencia rápida para auditoría y pruebas.

---

## 3. Chuleta para los 3 Ejercicios Típicos en Vivo del Entrevistador

1. **Si te pide: *"Agrega en vivo un nuevo endpoint `GET /api/v1/health` en `template.yaml` sin usar IA"*:**
   - Vas a `ClaimsFunction` → sección `Events:` (**línea 269**) y copias las 6 líneas de `GetClaim` cambiando el nombre y la ruta:
     ```yaml
             HealthCheck:
               Type: Api
               Properties:
                 RestApiId: !Ref SiniestrosApi
                 Path: /api/v1/health
                 Method: GET
     ```
   - *(Nuestro `backend/claims/index.mjs` ya responde a `/health`, o puedes apuntarlo a una función de 5 líneas)* y ejecutas `sam build && sam deploy --config-env dev`.
2. **Si te pide: *"Despliega una copia nueva del stack con otro nombre"*:**
   - Ejecutas `sam deploy --stack-name siniestros-demo2 --parameter-overrides ProjectName=siniestros2 Env=dev --resolve-s3 --capabilities CAPABILITY_IAM`. Como todos los recursos usan `${ProjectName}-${Env}-...`, ¡se crea entero sin chocar con ningún bucket ni tabla existente!
3. **Si te pide: *"Rompí algo en el template y da Error 500 al guardar un siniestro, diagnostícalo"*:**
   - Miras dos lugares en `ClaimsFunction` (**líneas 237–250** y **líneas 79–83**):
     - ¿Le quitaron `DynamoDBCrudPolicy` o `KMSDecryptPolicy` en `Policies`? (En CloudWatch Logs verás `AccessDeniedException`).
     - ¿Cambiaron mal el nombre de la variable `CLAIMS_TABLE_NAME` en `Globals.Function.Environment`? (En CloudWatch Logs verás `ResourceNotFoundException`).

