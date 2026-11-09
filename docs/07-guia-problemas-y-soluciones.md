# Guía de Sustentación: Resolución Detallada de los 7 Problemas Actuales

Este documento explica paso a paso cada problema de la sección **"Situación Actual (Problemas)"** del PDF: por qué era crítico para la aseguradora, qué solución técnica implementamos, qué archivos del proyecto intervienen y en qué parte exacta del flujo integral se ejecuta.

---

## Problema 1: Despliegue Manual
> **Enunciado del PDF:** *"1. Despliegue manual: El equipo despliega ejecutando comandos de CloudFormation directamente desde sus máquinas locales o desde la consola AWS."*

### 1.1 ¿Por qué era un riesgo grave en la aseguradora (HDI / SFC)?
1. **Falta de Auditoría y Trazabilidad (Riesgo SFC):** Cuando alguien despliega desde su laptop o modifica un recurso en la consola web de AWS, no queda rastro centralizado de qué commit exacto se desplegó, con qué parámetros se corrió ni quién aprobó el paso a producción.
2. **Inconsistencia y Error Humano ("En mi máquina sí funcionaba"):** Cada desarrollador tenía versiones distintas de AWS CLI/SAM o pasaba parámetros manuales distintos en la línea de comandos, provocando fallos inesperados al subir cambios.
3. **Exceso de Privilegios IAM:** Obligaba a entregar credenciales de AWS con permisos de escritura en Producción a las máquinas locales de los desarrolladores.

---

### 1.2 Solución Implementada en Nuestro Proyecto

Eliminamos por completo los despliegues manuales desde máquinas locales y consola mediante **3 componentes automatizados**:

#### A) Perfiles Declarativos de Despliegue por Ambiente (`infra/samconfig.toml`)
En lugar de escribir comandos largos a mano, creamos [`infra/samconfig.toml`](../infra/samconfig.toml) con tres bloques estandarizados (`[dev.deploy.parameters]`, `[staging.deploy.parameters]`, `[prod.deploy.parameters]`) que fijan:
- `stack_name = "siniestros-<env>"`
- `region = "us-east-1"`
- `resolve_s3 = true` (SAM gestiona automáticamente el bucket de artefactos sin intervención manual)
- `confirm_changeset = false` y `fail_on_empty_changeset = false` (para ejecución 100% desatendida desde Jenkins)
- `parameter_overrides` y `tags` obligatorios (`Project=siniestros`, `DataClassification=PII-Confidential`, `Compliance=SFC-CE007-2018`)

#### B) Ejecución Automatizada de Infraestructura y Backend desde Jenkins (`Jenkinsfile`)
En las **Etapas 5 (`Deploy to DEV`), 6 (`Deploy to STAGING`) y 8 (`Deploy to PROD`)** del [`Jenkinsfile`](../Jenkinsfile), el servidor de integración continua es quien ejecuta el despliegue contra AWS CloudFormation:
```bash
sam deploy \
  --template-file infra/template.yaml \
  --config-file infra/samconfig.toml \
  --config-env dev \
  --region "us-east-1"
```
Para Producción (`Stage 7`), antes de ejecutar `sam deploy --config-env prod`, Jenkins exige una **Aprobación Manual (`input`)** que guarda el usuario aprobador (`APPROVER_USER`) en el log del build para auditoría.

#### C) Despliegue Automatizado del Frontend SPA + Invalidación de CDN (`scripts/deploy-frontend.sh`)
Antes también subían los archivos del frontend manualmente al bucket S3 desde la consola de AWS. Ahora el script [`scripts/deploy-frontend.sh`](../scripts/deploy-frontend.sh) automatiza los 4 pasos sin intervención humana:
1. Consulta dinámicamente los `Outputs` del stack recién desplegado (`FrontendBucketName` y `CloudFrontDistributionId`) con `aws cloudformation describe-stacks`.
2. Sincroniza los assets hacia S3 con `aws s3 sync --delete`.
3. Sube `index.html` con cabecera `Cache-Control: no-cache, no-store, must-revalidate`.
4. Ejecuta `aws cloudfront create-invalidation --paths "/index.html" "/"` para actualizar la caché de CloudFront en segundos.

---

### 1.3 ¿En qué parte del flujo integral del proyecto se encuentra? (Tabla de Flujo)

| Orden | Etapa en el Flujo Integral | Acción Ejecutada | ¿Interviene la Solución al Problema #1? |
|---|---|---|---|
| **1** | **Push a GitHub** | El ingeniero hace `git push` a `develop`, `release/*` o `main`. | Inicia el proceso automático. |
| **2** | **`Stage 1: Checkout`** | Jenkins descarga el repositorio y detecta la rama destino. | Prepara el entorno sin intervención humana. |
| **3** | **`Stages 2, 3 y 4`** | Validación de parámetros, unit tests y escaneos DevSecOps. | Compuertas previas al despliegue. |
| **4** | **`Stages 5 (dev), 6 (staging) y 8 (prod)`** | **Paso A:** Ejecuta `sam deploy --config-env <env>` (actualiza CloudFormation, Lambdas, API Gateway y DynamoDB). | **🎯 SÍ — Aquí actúa directamente (`Jenkinsfile` + `samconfig.toml`).** |
| **5** | **`Stages 5, 6 y 8` (Frontend)** | **Paso B:** Ejecuta `bash scripts/deploy-frontend.sh <env>` (sincroniza S3 privado e invalida CloudFront). | **🎯 SÍ — Elimina la subida manual de archivos al bucket S3.** |
| **6** | **`Stages 5, 6 y 8` (Verificación)** | **Paso C:** Ejecuta `bash scripts/smoke-test.sh <env>` (verifica con `curl` que los endpoints respondan HTTP 200/201). | **🎯 SÍ — Valida automáticamente que el despliegue quedó operativo.** |

- **Ubicación en tu Diagrama de Arquitectura (`entrevista_hdi (1).jpg`):**
  Corresponde al flujo superior izquierdo: **`Devops` → `Github` → `Jenkins` → `CloudFormation` → `CodeDeploy`**.
- **Archivos exactos que intervienen:**
  1. [`Jenkinsfile`](../Jenkinsfile) (Etapas 5, 6, 7 y 8).
  2. [`infra/samconfig.toml`](../infra/samconfig.toml) (Perfiles de despliegue automatizado por ambiente).
  3. [`infra/template.yaml`](../infra/template.yaml) (Plantilla única de CloudFormation/SAM).
  4. [`scripts/deploy-frontend.sh`](../scripts/deploy-frontend.sh) (Automatización de S3 Frontend + CloudFront).
  5. [`scripts/smoke-test.sh`](../scripts/smoke-test.sh) (Verificación post-despliegue automática).

---

### 1.4 Guion Corto para Responder en la Sustentación (20 segundos)
> *"El Problema #1 era que desplegaban manualmente desde sus laptops o desde la consola de AWS, sin control ni trazabilidad. Lo solucionamos centralizando todo el despliegue en nuestro `Jenkinsfile` apoyado en `infra/samconfig.toml` y `scripts/deploy-frontend.sh`. Ahora nadie toca la consola manualmente: al subir un cambio a GitHub, Jenkins ejecuta `sam deploy --config-env <env>` para actualizar todo el stack de CloudFormation, sincroniza automáticamente el frontend al bucket S3, invalida la caché de CloudFront y corre un smoke test automático sobre los 4 endpoints."*



---

## Problema 2: Sin Pipeline CI/CD ni Validaciones Previas
> **Enunciado del PDF:** *"2. Sin pipeline CI/CD: No existe un flujo automatizado de build, test y deploy. Los cambios se suben directamente a las ramas sin validaciones previas."*

### 2.1 ¿Por qué era un riesgo grave en la aseguradora?
1. **Defectos detectados tarde (en Producción):** Al no existir validaciones previas (`lint`, pruebas unitarias ni validación de plantillas SAM), cualquier error de sintaxis en JavaScript o en el YAML de CloudFormation llegaba directo al ambiente de AWS, provocando caídas del servicio para los agentes en terreno.
2. **Ausencia de Pruebas Post-Despliegue (Smoke Tests):** Aunque CloudFormation terminara en `UPDATE_COMPLETE`, nadie verificaba automáticamente que los 4 endpoints REST (`/claims` y `/documents/report`) siguieran respondiendo `200`/`201`.
3. **Sin control de promoción entre ambientes:** Un cambio podía aplicarse en producción sin haber sido validado antes en `dev` y `staging` y sin aprobación formal.

---

### 2.2 Solución Implementada en Nuestro Proyecto

Implementamos un pipeline declarativo completo de **8 etapas en [`Jenkinsfile`](../Jenkinsfile)** que funciona como un sistema de compuertas secuenciales (*Quality Gates*): **ningún cambio puede desplegarse en AWS si no supera primero las etapas 2, 3 y 4**, y ningún cambio llega a `prod` sin pasar primero por `dev`, `staging` y la compuerta de aprobación manual.

#### Desglose de las 8 Etapas del `Jenkinsfile`:
| Etapa en `Jenkinsfile` | Fase CI/CD | Qué valida o ejecuta exactamente | Qué pasa si falla |
|---|---|---|---|
| **`Stage 1: Checkout & Metadata`** | **Checkout** | Descarga el código del repositorio, captura el hash del commit (`GIT_COMMIT_SHORT`) y prepara `reports/`. | Se aborta el build. |
| **`Stage 2: Validate Environment Config & IaC`** | **Validación Previa (IaC & Config)** | 1) Ejecuta [`scripts/validate-params.sh`](../scripts/validate-params.sh) (`check-jsonschema` sobre `dev.json`, `staging.json`, `prod.json`).<br>2) Ejecuta `sam validate -t infra/template.yaml`. | **Bloquea el pipeline** antes de compilar o tocar AWS. |
| **`Stage 3: Build & Unit Tests`** | **Build & Test** | 1) En `backend/`: ejecuta `npm run lint` (`node --check` sobre las 2 Lambdas) y `npm test` ([`backend/tests/backend.test.mjs`](../backend/tests/backend.test.mjs) validando `maskPii()` y respuestas HTTP).<br>2) En `frontend/`: ejecuta `npm run build` generando `frontend/dist/index.html`. | **Bloquea el pipeline** si hay un error de sintaxis o si falla un test unitario. |
| **`Stage 4: Security Scan + AI Triage`** | **Security Scan** | Ejecuta en paralelo **Gitleaks**, **Semgrep**, **npm audit** y **Checkov**, y genera `reports/security-summary.md` con **Amazon Bedrock**. | **Bloquea el pipeline** si detecta secretos o vulnerabilidades críticas. |
| **`Stage 5: Deploy to DEV & Smoke Tests`** | **Deploy DEV + Test E2E** | Ejecuta `sam deploy --config-env dev`, sube el frontend (`deploy-frontend.sh dev`), corre pruebas E2E reales con `curl` (`smoke-test.sh dev`) y publica métricas DORA. | No promueve a `staging` y dispara análisis de fallo con IA (`post { failure }`). |
| **`Stage 6: Deploy to STAGING & Integration Tests`** | **Deploy STAGING + QA** | Despliega en `staging` con estrategia `Linear10PercentEvery1Minute` y ejecuta las pruebas de integración E2E (`smoke-test.sh staging`). | No llega a la aprobación de producción. |
| **`Stage 7: Manual Approval for PRODUCTION`** | **Governance Gate (SFC)** | Muestra en consola el dictamen de seguridad `reports/security-summary.md` y pausa esperando confirmación manual (`input`), guardando `APPROVER_USER`. | Si se rechaza o expira el timeout (24 h), se cancela el paso a `prod`. |
| **`Stage 8: Deploy to PROD`** | **Deploy PROD (Canary)** | Despliega en `prod` con `Canary10Percent5Minutes` + WAF activo + sincronización S3/CloudFront + `smoke-test.sh prod` + métricas DORA. | Si salta una alarma CloudWatch, CodeDeploy hace **Auto-Rollback en < 1 min**. |

---

### 2.3 ¿En qué parte del flujo integral del proyecto se encuentra? (Tabla de Flujo)

| Orden | Fase del Flujo | Acción y Compuerta de Calidad | Condición para Avanzar al Siguiente Paso |
|---|---|---|---|
| **1** | **Commit / Push a GitHub** | El desarrollador o DevOps sube cambios al repositorio. | Dispara automáticamente el `Jenkinsfile`. |
| **2** | **FASE CI (`Stages 1, 2, 3 y 4`)** | • `Stage 1`: Checkout.<br>• `Stage 2`: JSON Schema + `sam validate`.<br>• `Stage 3`: Lint + Unit Tests (`backend.test.mjs`) + Build Frontend.<br>• `Stage 4`: Gitleaks + Semgrep + npm audit + Checkov + Bedrock AI. | **¿Todo en verde?** Si falla cualquiera, bloquea el pipeline antes de tocar AWS. |
| **3** | **FASE CD — Ambiente `dev` (`Stage 5`)** | `sam deploy --config-env dev` + `deploy-frontend.sh dev` + `smoke-test.sh dev`. | Los endpoints de `dev` deben responder HTTP 200/201. |
| **4** | **FASE CD — Ambiente `staging` (`Stage 6`)** | `sam deploy --config-env staging` (`Linear10PercentEvery1Minute`) + `deploy-frontend.sh staging` + `smoke-test.sh staging`. | Las pruebas de integración E2E en `staging` deben pasar en verde. |
| **5** | **Compuerta de Gobierno (`Stage 7`)** | Muestra el dictamen `reports/security-summary.md` de Bedrock y solicita aprobación manual (`input`). | Un aprobador autorizado debe confirmar el paso (registra `APPROVER_USER`). |
| **6** | **FASE CD — Ambiente `prod` (`Stage 8`)** | `sam deploy --config-env prod` (`Canary10Percent5Minutes`) + WAFv2 activo + invalidación CloudFront + `smoke-test.sh prod` + métricas DORA. | CodeDeploy vigila las 3 alarmas de CloudWatch durante 5 minutos. |

- **Archivos exactos que intervienen:**
  1. [`Jenkinsfile`](../Jenkinsfile) (Orquestador de las 8 etapas y del bloque `post { failure }`).
  2. [`backend/package.json`](../backend/package.json) y [`backend/tests/backend.test.mjs`](../backend/tests/backend.test.mjs) (Comandos `npm run lint` y `npm test` de la Etapa 3).
  3. [`frontend/package.json`](../frontend/package.json) (Comando `npm run build` de la Etapa 3).
  4. [`scripts/smoke-test.sh`](../scripts/smoke-test.sh) (Pruebas E2E automatizadas post-despliegue sobre los 4 endpoints).

---

### 2.4 Guion Corto para Responder en la Sustentación (20 segundos)
> *"El Problema #2 era que subían cambios directo a las ramas sin un flujo automatizado de build, test ni validaciones previas. Lo resolvimos construyendo el `Jenkinsfile` declarativo de 8 etapas: antes de permitir cualquier despliegue a AWS, el pipeline valida los parámetros con JSON Schema y la plantilla con `sam validate` (Etapa 2), verifica la sintaxis de las Lambdas y corre las pruebas unitarias con `node --test` (Etapa 3), y ejecuta los 4 escáneres de seguridad en paralelo (Etapa 4). Solo si todo pasa en verde, promueve secuencialmente por `dev` y `staging` corriendo `smoke-test.sh` contra los 4 endpoints reales antes de pedir aprobación manual para `prod`."*


---

## Problema 3: Sin Análisis de Seguridad (SAST, SCA, Secretos ni IaC Scan)
> **Enunciado del PDF:** *"3. Sin análisis de seguridad: No se ejecutan escaneos de código estático (SAST), análisis de dependencias (SCA) ni validación de IaC antes del despliegue."*

### 3.1 ¿Por qué era un riesgo grave en la aseguradora (SFC)?
1. **Exposición de credenciales:** Sin un escáner de secretos, una llave `AKIA...` o contraseña subida por error al repositorio quedaba expuesta sin que nadie lo notara.
2. **Código o dependencias vulnerables en producción:** Sin SAST ni SCA, fallos de seguridad en el código de las Lambdas o CVEs críticos en librerías llegaban directamente al entorno productivo que maneja datos personales (PII).
3. **Recursos AWS mal configurados (IaC):** Sin escaneo de la plantilla `template.yaml`, un cambio podía desactivar por error el cifrado KMS de DynamoDB o el bloqueo de acceso público de un bucket S3, violando la **Circular Externa 007 de 2018 de la SFC**.

---

### 3.2 Solución Implementada en Nuestro Proyecto

Implementamos una **compuerta DevSecOps en paralelo en la Etapa 4 (`Stage 4: Security Scan (DevSecOps Gate + AI Triage)`)** del [`Jenkinsfile`](../Jenkinsfile) (complementada con la Etapa 2 de validación de esquemas e IaC), seguida de una política formal de **Bloqueo vs. Advertencia** en [`.security-exceptions.yaml`](../.security-exceptions.yaml) y el **Triage Inteligente con Amazon Bedrock**:

| Categoría Solicitada | Herramienta Integrada | Etapa del `Jenkinsfile` | Qué analiza exactamente | Reporte Generado en `reports/` |
|---|---|---|---|---|
| **1. Escaneo de Secretos** | **Gitleaks** | `Stage 4a` (Paralelo) | Escanea `backend/`, `frontend/` e `infra/` buscando llaves AWS, tokens o credenciales expuestas (`--redact`). | `reports/gitleaks-backend.json`, `gitleaks-frontend.json`, `gitleaks-infra.json` |
| **2. Código Estático (SAST)** | **Semgrep** | `Stage 4b` (Paralelo) | Analiza el código JavaScript de las Lambdas [`claims/index.mjs`](../backend/claims/index.mjs) y [`documents/index.mjs`](../backend/documents/index.mjs) contra reglas OWASP. | `reports/semgrep-sast.json` |
| **3. Dependencias (SCA)** | **npm audit** | `Stage 4c` (Paralelo) | Audita las dependencias en busca de vulnerabilidades CVE de severidad `HIGH` o `CRITICAL`. | `reports/npm-audit-backend.json` |
| **4. Validación de IaC** | **Checkov + sam validate + check-jsonschema** | `Stage 2` y `Stage 4d` (Paralelo) | Verifica que `infra/template.yaml` tenga cifrado KMS, bloqueo público S3, PITR en DynamoDB y permisos IAM acotados, y que `params/*.json` cumplan con `schema.json`. | `reports/checkov-iac.json` |
| **5. Triage con IA (Plus)** | **Amazon Bedrock (`nova-micro-v1:0`)** | `Stage 4 -> post { success }` | Ejecuta [`scripts/ai-devops-assistant.sh triage`](../scripts/ai-devops-assistant.sh) para resumir los hallazgos bajo normativa SFC y presentarlos en la aprobación de `prod`. | `reports/security-summary.md` |

#### Política de Bloqueo vs. Advertencia ([`.security-exceptions.yaml`](../.security-exceptions.yaml)):
- **Bloqueo Inmediato (`exit 1` — No despliega):**
  - Cualquier secreto detectado por **Gitleaks**.
  - Cualquier vulnerabilidad **`CRITICAL`** o **`HIGH` con solución disponible** en SAST, SCA o IaC.
- **Advertencia (`Warning` — Permite continuar con seguimiento):**
  - Vulnerabilidades **`MEDIUM`** (SLA de remediación: 30 días) y **`LOW`** (SLA: 90 días).
  - Reglas de IaC con excepción arquitectónica justificada, firmada y con fecha de caducidad en [`.security-exceptions.yaml`](../.security-exceptions.yaml) (por ejemplo, `CKV_AWS_117` sobre no meter Lambdas 100% serverless en una VPC por costos de NAT Gateway/Interface Endpoints).

---

### 3.3 ¿En qué parte del flujo integral del proyecto se encuentra? (Tabla de Flujo)

| Orden | Etapa en el Flujo Integral | Acción Ejecutada | Resultado / Compuerta |
|---|---|---|---|
| **1** | **`Stage 3: Build & Unit Tests`** | Código compilado y pruebas unitarias en verde. | Habilita el inicio del escaneo de seguridad. |
| **2** | **`Stage 4: Security Scan` (4 hilos en paralelo)** | **🎯 AQUÍ ACTÚA LA SOLUCIÓN AL PROBLEMA #3:**<br>• **4a. Gitleaks:** Escaneo de secretos.<br>• **4b. Semgrep:** SAST sobre código JS.<br>• **4c. npm audit:** SCA de dependencias.<br>• **4d. Checkov:** Seguridad de IaC (`template.yaml`). | Genera los 4 reportes JSON en `reports/`. Si hay secreto o hallazgo `CRITICAL`/`HIGH`, bloquea el pipeline (`exit 1`). |
| **3** | **`Post-Stage 4: AI Triage`** | Ejecuta `scripts/ai-devops-assistant.sh triage` con **Amazon Bedrock (`nova-micro-v1:0`)**. | Genera `reports/security-summary.md` con dictamen ejecutivo para auditoría SFC. |
| **4** | **`Stage 5 / 6 / 8: Deploy a AWS`** | Despliegue con `sam deploy`. | Solo se ejecuta si el Quality Gate de seguridad fue aprobado. |

- **Archivos exactos que intervienen:**
  1. [`Jenkinsfile`](../Jenkinsfile) (Líneas 50–67 para `Stage 2` y Líneas 86–127 para `Stage 4` en paralelo).
  2. [`.security-exceptions.yaml`](../.security-exceptions.yaml) (Política de Quality Gates, SLAs y excepciones auditadas).
  3. [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) (Triage automatizado de los reportes con Amazon Bedrock).
  4. Carpeta [`reports/`](../reports/) (Artefactos JSON y Markdown archivados en cada build de Jenkins para auditoría SFC).

---

### 3.4 Guion Corto para Responder en la Sustentación (20 segundos)
> *"El Problema #3 era que desplegaban sin ejecutar escaneos SAST, SCA ni validación de IaC. Lo solucionamos en la Etapa 4 del `Jenkinsfile` ejecutando 4 escáneres en paralelo antes de cualquier despliegue: **Gitleaks** para secretos, **Semgrep** para SAST sobre el código de las Lambdas, **npm audit** para SCA de dependencias, y **Checkov** junto con `sam validate` y `check-jsonschema` para validar la seguridad y estructura de IaC. Además definimos en `.security-exceptions.yaml` una política donde hallazgos Críticos/Altos o secretos bloquean el pipeline, mientras que Medios/Bajos generan advertencia con SLA y son resumidos por **Amazon Bedrock** en `security-summary.md` para el aprobador de producción."*


---

## Problema 4: Sin Observabilidad, Dashboards, Alertas ni Trazabilidad End-to-End
> **Enunciado del PDF:** *"4. Sin observabilidad: Los logs existen en CloudWatch pero no hay dashboards, alertas ni trazabilidad end-to-end. Cuando hay un incidente, el diagnóstico es manual."*

### 4.1 ¿Por qué era un riesgo grave en la aseguradora?
1. **Detección reactiva de incidentes:** Sin alarmas configuradas, cuando las Lambdas o el API Gateway fallaban, el equipo de operaciones solo se enteraba cuando los agentes de seguros reportaban que no podían registrar siniestros.
2. **Alto tiempo de diagnóstico (MTTR elevado):** Sin trazabilidad distribuida (**AWS X-Ray**) ni logs estructurados en JSON, rastrear si una falla provenía del API Gateway, del código de la Lambda, de un permiso en KMS/S3 o de DynamoDB requería revisar logs de texto manualmente durante horas.
3. **Sin medición de desempeño DevOps (Métricas DORA):** No existía un tablero centralizado que mostrara la salud técnica de la aplicación ni las métricas de entrega continua.

---

### 4.2 Solución Implementada en Nuestro Proyecto

Implementamos un stack de observabilidad 100% nativo y definido como código dentro de [`infra/template.yaml`](../infra/template.yaml) (Sección **6. OBSERVABILIDAD**), complementado con [`scripts/dora-metrics.sh`](../scripts/dora-metrics.sh) y [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh):

| Necesidad del PDF | Componente Implementado | Dónde está definido | Qué hace exactamente |
|---|---|---|---|
| **1. Trazabilidad End-to-End** | **AWS X-Ray** | `infra/template.yaml` (`Tracing: Active` en `Globals.Function` y `TracingEnabled: true` en `SiniestrosApi`) | Traza cada petición de extremo a extremo (`API Gateway → Lambda → DynamoDB / S3 / Secrets Manager`) y genera el mapa de servicios con latencias por componente. |
| **2. Logs Estructurados y Protección PII desde DevOps (IaC)** | **Lambda `LoggingConfig: LogFormat: JSON` + CloudWatch Logs Data Protection** | `infra/template.yaml` (`Globals.Function.LoggingConfig`) | Fuerza desde la infraestructura (sin depender del desarrollador backend) que AWS Lambda capture todos los logs en formato **JSON estructurado** (`timestamp`, `level`, `requestId`), complementado con políticas de enmascaramiento de PII en CloudWatch Logs y `maskPii()` en aplicación. |
| **3. Alertas Críticas + Notificación** | **3 CloudWatch Alarms + Amazon SNS (`AlertsTopic`)** | `infra/template.yaml` (Líneas 390–446) | • `ClaimsFunctionErrorsAlarm`: dispara si `Errors >= 1` en 1 min.<br>• `DocumentsFunctionErrorsAlarm`: dispara si `Errors >= 1` en 1 min.<br>• `ApiGateway5xxAlarm`: dispara si `5XXError >= 2` en 1 min.<br>Todas notifican a **SNS** y activan el **Auto-Rollback en CodeDeploy**. |
| **4. Dashboards Operativos** | **CloudWatch Dashboard (`ObservabilityDashboard`)** | `infra/template.yaml` (Líneas 448–505) | Crea automáticamente el tablero `siniestros-${Env}-operations-dora` con gráficas de peticiones/5XX en API Gateway, invocaciones/errores de las 2 Lambdas y las 4 métricas DORA. |
| **5. Medición de Métricas DORA** | **Script `dora-metrics.sh` -> CloudWatch Custom Metrics** | [`scripts/dora-metrics.sh`](../scripts/dora-metrics.sh) | Publica automáticamente en el namespace `SiniestrosDORA`: `DeploymentFrequency`, `LeadTimeMinutes` (calculado desde el commit en Git), `ChangeFailureCount` y `MeanTimeToRestoreMinutes`. |
| **6. Diagnóstico Asistido por IA** | **Amazon Bedrock RCA (`ai-devops-assistant.sh failure`)** | `Jenkinsfile` (`post { failure }`) | Si ocurre un fallo, analiza el log sanitizado con `amazon.nova-micro-v1:0` y entrega causa raíz y comando de corrección en `reports/ai-failure-analysis.md`. |

---

### 4.3 ¿En qué parte del flujo integral del proyecto se encuentra? (Tabla de Flujo)

| Momento | Paso en el Flujo | Componente | Qué registra o dispara |
|---|---|---|---|
| **1. En Tiempo de Ejecución (Tráfico de Agentes)** | **Paso A: Entrada a API Gateway** | `SiniestrosApi` | Inicia el segmento de traza **AWS X-Ray** (`TracingEnabled: true`) y mide errores `5XX`. |
| **1. En Tiempo de Ejecución (Tráfico de Agentes)** | **Paso B: Ejecución de Lambdas** | `ClaimsFunction` / `DocumentsFunction` | Propaga la traza **X-Ray** (`Tracing: Active`) hacia DynamoDB/S3 y emite logs en **JSON** (`LogFormat: JSON`). |
| **1. En Tiempo de Ejecución (Tráfico de Agentes)** | **Paso C: Centralización y Enmascaramiento** | **Amazon CloudWatch** | Aplica `DataProtectionPolicy` (`*****`), grafica en `ObservabilityDashboard` y evalúa las **3 Alarmas** cada minuto. |
| **1. En Tiempo de Ejecución (Tráfico de Agentes)** | **Paso D: Respuesta Automática ante Fallo** | **Amazon SNS + AWS CodeDeploy** | Si `Errors >= 1` o `5XXError >= 2`, envía alerta a **SNS (`AlertsTopic`)** y dispara **Rollback Automático en CodeDeploy (< 1 min)**. |
| **2. En cada Ejecución del Pipeline (`Jenkinsfile`)** | **Paso E: Publicación DORA y RCA** | `scripts/dora-metrics.sh` + `ai-devops-assistant.sh` | Publica `DeploymentFrequency`, `LeadTimeMinutes`, `ChangeFailureCount` y `MTTR` en CloudWatch, y si algo falla genera diagnóstico con **Bedrock**. |

- **Ubicación en tu Diagrama de Arquitectura (`entrevista_hdi (1).jpg`):**
  Es la caja superior derecha **`Observability Tooling`** (`CloudWatch`, `SNS`, `CloudTrail`, `X-Ray`) conectada con `CodeDeploy`.
- **Archivos exactos que intervienen:**
  1. [`infra/template.yaml`](../infra/template.yaml) (Líneas 66, 183 y 390–505: X-Ray, SNS, 3 Alarmas y Dashboard).
  2. [`scripts/dora-metrics.sh`](../scripts/dora-metrics.sh) (Publicación de métricas DORA en CloudWatch).
  3. [`backend/claims/index.mjs`](../backend/claims/index.mjs) y [`backend/documents/index.mjs`](../backend/documents/index.mjs) (Logs JSON estructurados).
  4. [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) (Diagnóstico automático de fallos con Bedrock).

---

### 4.4 Guion Corto para Responder en la Sustentación (20 segundos)
> *"El Problema #4 era que solo tenían logs sueltos en CloudWatch sin dashboards, alertas ni trazabilidad, haciendo lento cualquier diagnóstico. Lo solucionamos en `infra/template.yaml` habilitando **AWS X-Ray** de extremo a extremo entre API Gateway, Lambdas, DynamoDB y S3; estandarizando logs en JSON; aprovisionando el **CloudWatch Dashboard** `siniestros-operations-dora` y configurando **3 alarmas críticas** (errores en `claims`, errores en `documents` y `5XX` en API Gateway) conectadas a **SNS** y al **Rollback automático de CodeDeploy**, además de publicar automáticamente las **4 métricas DORA** desde el pipeline con `scripts/dora-metrics.sh`."*


---

## Problema 5: Configuración Inconsistente entre Ambientes
> **Enunciado del PDF:** *"5. Configuración inconsistente: Los archivos de environment se editan manualmente y no hay validación de que los parámetros sean correctos antes de desplegar."*

### 5.1 ¿Por qué era un riesgo grave en la aseguradora?
1. **Configuration Drift (Deriva de Configuración):** Al editar parámetros a mano antes de cada despliegue, `dev`, `staging` y `prod` terminaban con configuraciones distintas o con variables mal escritas (*typos*).
2. **Fallos tardíos en CloudFormation:** Si alguien ponía un valor inválido (por ejemplo, una memoria de Lambda fuera de rango, un runtime deprecado como `nodejs20.x` o un tipo de despliegue mal escrito), el error recién aparecía a mitad del despliegue en AWS, dejando el stack en `UPDATE_ROLLBACK_COMPLETE`.

---

### 5.2 Solución Implementada en Nuestro Proyecto

Resolvimos este problema desde **Infraestructura como Código (IaC)** mediante **3 mecanismos combinados**:

1. **Archivos de Parámetros Versionados en Git por Ambiente (`infra/params/*.json` y `infra/samconfig.toml`):**
   - [`infra/params/dev.json`](../infra/params/dev.json), [`infra/params/staging.json`](../infra/params/staging.json) y [`infra/params/prod.json`](../infra/params/prod.json) definen exactamente los 7 parámetros de cada ambiente (`Env`, `NodeRuntime`, `LambdaMemorySize`, `LambdaTimeout`, `DeploymentPreferenceType`, `EnableWaf`, `LogRetentionDays`).
   - [`infra/samconfig.toml`](../infra/samconfig.toml) mapea cada ambiente (`[dev.deploy.parameters]`, `[staging.deploy.parameters]`, `[prod.deploy.parameters]`) para que `sam deploy --config-env <env>` inyecte siempre los parámetros exactos sin edición manual.
2. **Contrato de Validación Estricta con JSON Schema ([`infra/params/schema.json`](../infra/params/schema.json)):**
   - Define el tipo exacto (`string`, `integer`), los rangos permitidos (`minimum: 128`, `maximum: 3008`), las listas blancas (`enum: ["dev", "staging", "prod"]`, `enum: ["nodejs22.x", "nodejs24.x"]`) y prohíbe propiedades desconocidas (`"additionalProperties": false`).
3. **Validación Automática Pre-Despliegue en el Pipeline ([`scripts/validate-params.sh`](../scripts/validate-params.sh)) + `AllowedValues` en `template.yaml`:**
   - En la **Etapa 2 (`Stage 2: Validate Environment Config & IaC`)** del [`Jenkinsfile`](../Jenkinsfile), el script `scripts/validate-params.sh` ejecuta `check-jsonschema` sobre los 3 archivos `.json`. Si un solo parámetro es inválido o falta, **el pipeline se detiene en el segundo 2** antes de siquiera compilar o llamar a AWS.
   - Adicionalmente, la sección `Parameters` de [`infra/template.yaml`](../infra/template.yaml) (Líneas 9–55) define `AllowedValues`, `MinValue` y `MaxValue` como segunda barrera nativa en CloudFormation.

---

### 5.3 ¿En qué parte del flujo integral del proyecto se encuentra? (Tabla de Flujo)

| Orden | Etapa en el Flujo Integral | Acción Ejecutada | Resultado si pasa / si falla |
|---|---|---|---|
| **1** | **`Stage 1: Checkout`** | Jenkins clona el repositorio con `infra/params/*.json`, `schema.json` y `template.yaml`. | Pasa a la Etapa 2. |
| **2** | **`Stage 2: Validate Config` (Paso A)** | **🎯 AQUÍ ACTÚA LA SOLUCIÓN AL PROBLEMA #5:** Ejecuta `bash scripts/validate-params.sh` comparando `dev.json`, `staging.json` y `prod.json` contra `infra/params/schema.json` y reglas SFC. | • **¿Algún parámetro inválido?** ❌ Bloquea el pipeline en < 5 seg sin tocar AWS.<br>• **¿Todo válido?** ✅ Avanza al Paso B. |
| **3** | **`Stage 2: Validate IaC` (Paso B)** | Ejecuta `sam validate -t infra/template.yaml` verificando sintaxis y `Parameters` (`AllowedValues`). | Si es válido, autoriza pasar a `Stage 3 (Build)` y luego a `sam deploy --config-env <env>`. |

- **Archivos exactos que intervienen:**
  1. [`infra/params/schema.json`](../infra/params/schema.json) (Esquema de reglas y tipos permitidos).
  2. [`infra/params/dev.json`](../infra/params/dev.json), [`staging.json`](../infra/params/staging.json) y [`prod.json`](../infra/params/prod.json) (Parámetros de cada ambiente versionados en Git).
  3. [`scripts/validate-params.sh`](../scripts/validate-params.sh) (Script validador ejecutado en la Etapa 2 de Jenkins).
  4. [`infra/samconfig.toml`](../infra/samconfig.toml) y [`infra/template.yaml`](../infra/template.yaml) (`Parameters` con `AllowedValues` y `Conditions`).

---

### 5.4 Guion Corto para Responder en la Sustentación (20 segundos)
> *"El Problema #5 era que editaban los archivos de configuración manualmente sin validar que los parámetros fueran correctos antes de desplegar. Lo solucionamos manteniendo un único `infra/template.yaml` parametrizado junto con archivos versionados por ambiente (`dev.json`, `staging.json`, `prod.json`) y `samconfig.toml`. En la Etapa 2 del `Jenkinsfile`, antes de hacer cualquier build o tocar AWS, ejecutamos `scripts/validate-params.sh` que valida los 3 archivos contra `infra/params/schema.json` usando `check-jsonschema`, garantizando que si falta un parámetro o tiene un valor inválido el pipeline falle de inmediato."*

---

## Problema 6: Sin Estrategia de Rollback (Más de 1 hora manual)
> **Enunciado del PDF:** *"6. Sin estrategia de rollback: Si un despliegue falla en producción, el rollback es manual y puede tomar más de 1 hora."*

### 6.1 ¿Por qué era un riesgo grave en la aseguradora?
1. **Impacto del 100% en los usuarios (Blast Radius total):** Como antes reemplazaban la función Lambda de golpe (`AllAtOnce`), cualquier bug en el nuevo despliegue dejaba fuera de servicio al **100% de los agentes de seguros en terreno** inmediatamente.
2. **MTTR superior a 60 minutos:** Para revertir el fallo tenían que buscar qué código había antes, volver a empaquetarlo manualmente desde una máquina local y redesplegarlo en CloudFormation, tardando más de 1 hora con producción caída.

---

### 6.2 Solución Implementada en Nuestro Proyecto

Implementamos una estrategia de **Despliegue Gradual Canary con AWS CodeDeploy + Rollback Automático por Alarmas de CloudWatch**, reduciendo el tiempo de rollback de **> 1 hora a menos de 1 minuto (sin intervención humana)**:

#### A) Versionado Inmutable y Alias `live` en las Lambdas (`AutoPublishAlias: live`)
En [`infra/template.yaml`](../infra/template.yaml) (Líneas 202 y 249), tanto `ClaimsFunction` como `DocumentsFunction` tienen configurado `AutoPublishAlias: live`.
- Cada vez que se despliega un cambio, AWS Lambda **no sobrescribe** la versión anterior (ej. `Versión 1`), sino que publica una versión nueva inmutable (`Versión 2`) y el API Gateway apunta al alias `live`.

#### B) Desplazamiento Gradual de Tráfico con AWS CodeDeploy (`DeploymentPreference`)
En lugar de mandar todo el tráfico de golpe en producción, configuramos estrategias diferenciadas por ambiente mediante el parámetro `DeploymentPreferenceType`:
- **`dev`**: `AllAtOnce` (rápido para desarrollo).
- **`staging`**: `Linear10PercentEvery1Minute` (10% más cada minuto).
- **`prod`**: **`Canary10Percent5Minutes`**:
  - Durante los primeros **5 minutos**, CodeDeploy envía el **90% del tráfico a la versión anterior estable (`v1`)** y solo el **10% del tráfico a la versión nueva (`v2`)**.
  - Si durante esos 5 minutos todo funciona sin errores, CodeDeploy pasa el **100% a la `v2`**.

#### C) Rollback Automático en Segundos Conectado a Alarmas de CloudWatch (`Alarms`)
En el bloque `DeploymentPreference.Alarms` de ambas Lambdas en [`infra/template.yaml`](../infra/template.yaml) (Líneas 205–207 y 252–254), conectamos las alarmas:
- `ClaimsFunctionErrorsAlarm` (`Errors >= 1` en 60 segundos)
- `DocumentsFunctionErrorsAlarm` (`Errors >= 1` en 60 segundos)
- `ApiGateway5xxAlarm` (`5XXError >= 2` en 60 segundos)

**¿Qué ocurre si la nueva versión tiene un fallo?**
Apenas ocurre **1 solo error** en ese 10% de tráfico Canary, la alarma de CloudWatch pasa a estado `ALARM` y **AWS CodeDeploy corta automáticamente el despliegue y regresa el 100% del tráfico del alias `live` a la versión anterior (`v1`) en cuestión de segundos**, enviando además una alerta al tópico SNS `AlertsTopic`.

---

### 6.3 ¿En qué parte del flujo integral del proyecto se encuentra? (Tabla de Flujo)

| Orden | Etapa en el Flujo Integral | Acción Ejecutada | Qué ocurre si hay 0 errores vs. si hay fallo |
|---|---|---|---|
| **1** | **`Stage 8: Deploy to PROD`** | Jenkins ejecuta `sam deploy --config-env prod`. | CloudFormation publica una nueva versión inmutable de la Lambda (`v2`). |
| **2** | **Inicio de Canary en AWS CodeDeploy** | **🎯 AQUÍ ACTÚA LA SOLUCIÓN AL PROBLEMA #6:** CodeDeploy inicia `Canary10Percent5Minutes` sobre el alias `live`. | Durante 5 minutos mantiene **90% del tráfico en `v1`** (estable) y envía **10% del tráfico a `v2`** (nueva). |
| **3** | **Vigilancia Activa en CloudWatch** | CloudWatch evalúa cada 60 seg las 3 alarmas (`ClaimsFunctionErrorsAlarm`, `DocumentsFunctionErrorsAlarm`, `ApiGateway5xxAlarm`). | • **0 errores en 5 min:** ✅ Promueve el 100% del tráfico a `v2`.<br>• **`Errors >= 1` o `5XX >= 2`:** 🚨 **ROLLBACK AUTOMÁTICO (< 1 min)** — CodeDeploy regresa el 100% del alias `live` a `v1` y notifica a SNS. |

- **Ubicación en tu Diagrama de Arquitectura (`entrevista_hdi (1).jpg`):**
  Es la conexión directa en la parte superior central: **`CloudFormation` → `CodeDeploy` ← `CloudWatch` (y `CloudWatch` → `SNS`)**.
- **Archivos exactos que intervienen:**
  1. [`infra/template.yaml`](../infra/template.yaml) (Líneas 202–207 y 249–254: `AutoPublishAlias: live` + `DeploymentPreference` en las Lambdas; y Líneas 395–446: las 3 alarmas de CloudWatch).
  2. [`infra/params/prod.json`](../infra/params/prod.json) y [`infra/samconfig.toml`](../infra/samconfig.toml) (`DeploymentPreferenceType = Canary10Percent5Minutes`).
  3. [`Jenkinsfile`](../Jenkinsfile) (Auto-remediación para stacks en `ROLLBACK_COMPLETE` y rollback manual controlado por Git redesplegando versiones estables anteriores).

---

### 6.4 Guion Corto para Responder en la Sustentación (20 segundos)
> *"El Problema #6 era que si un despliegue fallaba en producción, el rollback era manual y tardaba más de 1 hora. Lo solucionamos en `infra/template.yaml` usando `AutoPublishAlias: live` y `DeploymentPreference` con **AWS CodeDeploy** en modo `Canary10Percent5Minutes` para producción. CodeDeploy solo envía el 10% del tráfico a la nueva versión de la Lambda durante 5 minutos mientras vigila las alarmas `ClaimsFunctionErrorsAlarm`, `DocumentsFunctionErrorsAlarm` y `ApiGateway5xxAlarm` en CloudWatch. Si ocurre un solo error en la Lambda o errores 5XX en el API Gateway, CodeDeploy revierte automáticamente el alias `live` a la versión anterior estable en menos de 1 minuto sin intervención humana."*


---

## Problema 7: Datos Sensibles (PII) y Regulación de la Superintendencia Financiera de Colombia (SFC)
> **Enunciado del PDF:** *"7. Datos sensibles: La aplicación maneja información personal de asegurados (PII) y debe cumplir con regulación de la Superintendencia Financiera de Colombia (SFC)."*

### 7.1 ¿Por qué era un riesgo grave en la aseguradora?
En Colombia, una aseguradora vigilada por la **SFC** debe cumplir con la **Ley Estatutaria 1581 de 2012 (Habeas Data)**, la **Circular Externa 007 de 2018 (Ciberseguridad)** y la **Circular Externa 005 de 2019 (Riesgos en Computación en la Nube)**. Exponer cédulas, nombres, teléfonos o reportes PDF de siniestros sin cifrado, sin control de acceso o en texto plano dentro de los logs conlleva sanciones regulatorias millonarias.

---

### 7.2 Solución Implementada desde DevOps / IaC (Sin Depender del Backend)

Como ingenieros **DevOps**, nuestra responsabilidad es garantizar que la **infraestructura en AWS (`infra/template.yaml`) y el Pipeline (`Jenkinsfile`)** protejan los datos personales (PII) por diseño, **incluso si un desarrollador backend olvida enmascarar un dato en su código**:

| Requisito Regulatorio SFC / Ley 1581 | Control Técnico 100% DevOps / IaC | Archivo y Ubicación Exacta |
|---|---|---|
| **1. Cifrado en Reposo con Llave Administrada por el Cliente (CMK)** | Recurso **`AppKmsKey` (`AWS::KMS::Key`)** con **rotación anual automática (`EnableKeyRotation: true`)** que cifra la tabla DynamoDB (`ClaimsTable`), el bucket de reportes PDF (`ReportsBucket`) y el secreto en `Secrets Manager`. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 86–113, 148–151 y 159–164) |
| **2. Enmascaramiento Automático de PII en CloudWatch Logs (`DataProtectionPolicy`)** | En el recurso **`ClaimsFunctionLogGroup` (`AWS::Logs::LogGroup`)**, activamos una **Política Nativa de Protección de Datos (`DataProtectionPolicy`)** de CloudWatch Logs (`Operation: Deidentify -> MaskConfig: {}`). Si una Lambda intenta imprimir un correo o credencial en texto plano, **AWS CloudWatch lo intercepta y lo reemplaza por `*****` antes de guardarlo en disco**, sin depender del código de los desarrolladores. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 196–224) |
| **3. Bloqueo Total de Acceso Público en S3 y Ciclo de Vida** | Tanto `ReportsBucket` como `FrontendBucket` tienen las **4 banderas de `PublicAccessBlockConfiguration: true`**, cifrado KMS y políticas de ciclo de vida (`LifecycleConfiguration`). El acceso al frontend es exclusivo mediante **CloudFront OAC (`SigV4`)**. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 153–170 y 291–336) |
| **4. Cifrado en Tránsito (HTTPS / TLS 1.2+) y Perímetro WAF + Cognito** | CloudFront fuerza `redirect-to-https`, activa **AWS WAFv2 (`AWSManagedRulesCommonRuleSet`)** en producción contra OWASP Top 10 e inyecciones, y el API Gateway exige autenticación con **Amazon Cognito User Pool (`AgentsUserPool`)**. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 171–194 y 338–418) |
| **5. Resiliencia, Backups y Prevención de Borrado Accidental** | En `ClaimsTable` está activo **Point-in-Time Recovery (`PITR`)** continuo de 35 días y en producción aplica `DeletionPolicy: Retain` y `UpdateReplacePolicy: Retain` para impedir pérdida de datos ante un borrado de stack. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 133–147) |
| **6. Retención de Logs y Auditoría de Cambios (SFC)** | En producción los logs se retienen por **365 días** (`RetentionInDays: 365`), el pipeline valida con **Checkov** que ningún desarrollador desactive KMS o `PublicAccessBlock`, y la **Etapa 7 del `Jenkinsfile`** registra qué usuario autorizó el paso a producción (`APPROVER_USER`). | [`infra/params/prod.json`](../infra/params/prod.json) y [`Jenkinsfile`](../Jenkinsfile) (Líneas 166–182) |
| **7. Sanitización de PII en el Pipeline antes de usar IA** | El script DevOps de IA filtra cualquier posible cédula o correo con expresiones regulares (`sanitize_pii`) antes de enviar logs a **Amazon Bedrock** dentro de la misma cuenta de AWS. | [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) (Líneas 21–24) |

---

### 7.3 ¿En qué parte del flujo integral del proyecto se encuentra? (Tabla de Flujo)

| Capa | Etapa / Componente | Qué control SFC / PII ejecuta |
|---|---|---|
| **1. Capa Preventiva en el Pipeline (`Jenkinsfile`)** | **`Stage 2: validate-params.sh`** | Exige que en `prod` el parámetro `LogRetentionDays` sea `>= 365` y `EnableWaf` sea `true`. |
| **1. Capa Preventiva en el Pipeline (`Jenkinsfile`)** | **`Stage 4: Gitleaks + Checkov`** | Verifica que no haya credenciales en Git y que `AppKmsKey`, `PublicAccessBlockConfiguration` y `PITR` sigan activos en `infra/template.yaml`. |
| **1. Capa Preventiva en el Pipeline (`Jenkinsfile`)** | **`Stage 7: Manual Approval`** | Registra la auditoría del usuario aprobador (`APPROVER_USER`) antes de desplegar en `prod`. |
| **2. Capa Protectiva en AWS Runtime (`infra/template.yaml`)** | **Perímetro (`WAFv2` + `CloudFront` + `Cognito`)** | Cifra el tráfico en tránsito (`TLS 1.2+`), filtra ataques OWASP, sirve el S3 privado por **OAC (`SigV4`)** y autentica agentes con **Cognito**. |
| **2. Capa Protectiva en AWS Runtime (`infra/template.yaml`)** | **Logs (`ClaimsFunctionLogGroup`)** | Intercepta los logs en tiempo real con **`DataProtectionPolicy` nativa** y reemplaza datos sensibles por `*****` antes de guardarlos en disco. |
| **2. Capa Protectiva en AWS Runtime (`infra/template.yaml`)** | **Datos en Reposo (`DynamoDB`, `S3`, `Secrets Manager`)** | Cifra todos los datos con nuestra llave **`AppKmsKey` (KMS CMK)** con rotación anual automática y mantiene **PITR (35 días)** + `DeletionPolicy: Retain`. |

- **Recorrido de extremo a extremo:**
  Tráfico cifrado por **WAFv2 + CloudFront (TLS 1.2+)** → **API Gateway (+ Cognito)** → **Logs interceptados y enmascarados por `DataProtectionPolicy` de CloudWatch** → **Datos en DynamoDB, S3 y Secrets Manager cifrados en reposo con nuestra llave `AppKmsKey` (KMS CMK)**.

---

### 7.4 Guion Corto para Responder en la Sustentación (20 segundos)
> *"Para resolver el Problema #7 (datos PII y regulación de la SFC) desde **DevOps sin depender de los desarrolladores backend**, implementamos controles nativos en `infra/template.yaml`: (1) cifrado en reposo con una llave propia **KMS CMK (`AppKmsKey`)** con rotación anual automática sobre DynamoDB, S3 y Secrets Manager; (2) una **Política Nativa de Protección de Datos (`DataProtectionPolicy`)** directamente en el `LogGroup` de CloudWatch que detecta y enmascara automáticamente datos sensibles con `*****` antes de guardarlos en el log; (3) buckets S3 100% privados (`PublicAccessBlock`) servidos por **OAC**; y (4) protección perimetral con **WAFv2**, **Cognito**, **PITR** en DynamoDB y retención de **365 días** validada por **Checkov** en el pipeline."*

---

## 8. Mapa de Flujo Integral de Todo el Proceso (Formato Tabla Detallada)

A continuación se presenta el recorrido completo, cronológico y paso a paso de todo el proyecto dividido en dos grandes tablas:
1. **Fase 1 (Tabla 8.1): Flujo del Pipeline CI/CD** (desde que se hace `git push` hasta que el código queda desplegado y medido en AWS).
2. **Fase 2 (Tabla 8.2): Flujo en Tiempo de Ejecución (Runtime en AWS)** (desde que el agente de seguros entra al portal hasta el almacenamiento cifrado, observabilidad y auto-rollback).

---

### 8.1 Fase 1: Flujo Paso a Paso del Pipeline CI/CD (`Jenkinsfile`)

| Paso | Etapa del Pipeline | ¿Qué ocurre exactamente? (Acción Técnica y Comandos) | Archivos Involucrados | Problema(s) del PDF que Resuelve | ¿Qué pasa si falla? (Control / Bloqueo) |
|---|---|---|---|---|---|
| **Paso 1** | **Disparo y `Stage 1: Checkout & Metadata`** | Se dispara el build con el parámetro `TARGET_ENV` (`dev`, `staging`, `prod` o cadena completa). Jenkins clona el repositorio, captura `GIT_COMMIT_SHORT` y ejecuta `rm -rf reports && mkdir -p reports` para asegurar limpieza total de artefactos de auditoría previos. | [`Jenkinsfile`](../Jenkinsfile) (Líneas 30–43) | **🎯 P1 (Despliegue manual):** Elimina el uso de consolas o máquinas locales; ningún humano ejecuta comandos sueltos en servidores. | Si el checkout o inicialización falla, el pipeline se aborta inmediatamente. |
| **Paso 2** | **`Stage 2: Validate IaC & Environment Params`** | Ejecuta 4 validaciones preventivas antes de compilar:<br>1. `jq empty` (sintaxis JSON de `dev.json`, `staging.json`, `prod.json`).<br>2. `check-jsonschema --schemafile schema.json` (valida tipos, enums y rangos).<br>3. Reglas de negocio en `validate-params.sh` (`prod` exige `LogRetentionDays >= 365`, `EnableWaf=true` y `Canary`/`Linear`).<br>4. `sam validate --lint` (valida sintaxis CloudFormation/SAM). | [`scripts/validate-params.sh`](../scripts/validate-params.sh)<br>[`infra/params/schema.json`](../infra/params/schema.json)<br>[`infra/params/*.json`](../infra/params/)<br>[`infra/template.yaml`](../infra/template.yaml) | **🎯 P5 (Configuración inconsistente):** Impide desplegar parámetros editados a mano con errores.<br>**🎯 P7 (Cumplimiento SFC):** Fuerza que `prod` siempre tenga 365 días de logs y WAF activo. | **Bloquea el pipeline inmediatamente (`exit 1`)** en menos de 5 segundos sin tocar AWS. |
| **Paso 3** | **`Stage 3: Build & Unit Tests`** | En paralelo compila y prueba:<br>• **Backend:** `npm ci`, `npm run lint` y `npm test` (ejecuta pruebas unitarias nativas en Node 22 validando creación de siniestros y generación de URLs prefirmadas).<br>• **Frontend:** `npm ci`, `npm run lint` y `npm run build` (genera `frontend/dist/index.html`). | [`backend/package.json`](../backend/package.json)<br>[`backend/tests/backend.test.mjs`](../backend/tests/backend.test.mjs)<br>[`frontend/package.json`](../frontend/package.json) | **🎯 P1 (Despliegue manual):** Estandariza la compilación y pruebas automáticas antes de empaquetar las Lambdas. | **Bloquea el pipeline (`exit 1`)** si cualquier test unitario o validación de sintaxis falla. |
| **Paso 4** | **`Stage 4: Security Scan (DevSecOps)` en Paralelo** | Corre 4 escáneres simultáneos:<br>• **4a. Gitleaks:** Busca llaves AWS, tokens o contraseñas en código e historial Git.<br>• **4b. Semgrep (SAST):** Analiza vulnerabilidades OWASP en `.mjs`.<br>• **4c. npm audit (SCA):** Busca CVEs `HIGH`/`CRITICAL` en librerías.<br>• **4d. Checkov (IaC):** Verifica en `template.yaml` que KMS, `PublicAccessBlock`, PITR e IAM de mínimo privilegio estén activos. | [`Jenkinsfile`](../Jenkinsfile) (Líneas 86–127)<br>[`.security-exceptions.yaml`](../.security-exceptions.yaml)<br>`reports/*.json` | **🎯 P2 (Credenciales en código):** Gitleaks impide subir secretos.<br>**🎯 P3 (Sin pruebas de seguridad):** Automatiza Secretos + SAST + SCA + IaC.<br>**🎯 P7 (Datos sensibles SFC):** Checkov garantiza cifrado KMS y privacidad S3. | • **Hallazgo `CRITICAL`/`HIGH` o Secreto:** **Bloquea el pipeline (`exit 1`)**.<br>• **Hallazgo `MEDIUM`/`LOW` o excepción vigente:** Genera **Warning** con SLA y continúa. |
| **Paso 5** | **`Post-Stage 4: Triage de Seguridad con IA (Bedrock)`** | Al terminar los 4 escáneres, ejecuta `ai-devops-assistant.sh triage`. El script sanitiza cualquier PII y envía los reportes JSON a **Amazon Bedrock (`amazon.nova-micro-v1:0`)**, generando un dictamen ejecutivo en Markdown con impacto regulatorio SFC. | [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh)<br>`reports/security-summary.md` | **🎯 P3 (Seguridad integrada)** y **Entregable 6 (IA en DevOps):** Traduce reportes técnicos crudos en una recomendación clara (`APROBAR` o `BLOQUEAR`). | Si Bedrock no responde, aplica fallback determinístico leyendo los JSON locales sin detener el pipeline. |
| **Paso 6** | **`Stages 5 y 6: Deploy a dev o staging + Smoke Test`** | 1. `sam build` + `sam deploy --config-env dev|staging` (crea/actualiza el stack `siniestros-dev` o `siniestros-staging`).<br>2. `deploy-frontend.sh` inyecta la URL real del API Gateway en el SPA, hace `aws s3 sync` al bucket privado e invalida CloudFront.<br>3. `smoke-test.sh` invoca `GET /health` y `POST /claims` verificando HTTP 200/201.<br>4. `dora-metrics.sh` publica métricas DORA en CloudWatch. | [`infra/samconfig.toml`](../infra/samconfig.toml)<br>[`scripts/deploy-frontend.sh`](../scripts/deploy-frontend.sh)<br>[`scripts/smoke-test.sh`](../scripts/smoke-test.sh)<br>[`scripts/dora-metrics.sh`](../scripts/dora-metrics.sh) | **🎯 P1 (Despliegue automatizado por ambiente)**.<br>**🎯 P4 (Observabilidad DORA)**.<br>**🎯 P5 (Ambientes aislados con la misma plantilla)**. | Si `sam deploy` o `smoke-test.sh` fallan, CloudFormation revierte el stack y se dispara el análisis de fallos con Bedrock. |
| **Paso 7** | **`Stage 7: Aprobación Manual para Producción` (Solo rama `main`)** | Antes de tocar `prod`, Jenkins pausa el pipeline (timeout de 60 min), muestra en pantalla el dictamen `reports/security-summary.md` generado por Bedrock y exige que un líder técnico/seguridad autorice el paso, guardando su usuario en `APPROVER_USER`. | [`Jenkinsfile`](../Jenkinsfile) (Líneas 166–182) | **🎯 P1 (Gobierno de cambios en prod)**.<br>**🎯 P7 (Trazabilidad y auditoría exigida por la SFC)**. | Si es rechazado o expira el timeout de 60 min, el pipeline aborta sin tocar `siniestros-prod`. |
| **Paso 8** | **`Stage 8: Deploy a Producción (Canary) + Smoke Test + DORA`** | 1. Ejecuta `sam deploy --config-env prod` sobre el stack `siniestros-prod`.<br>2. **AWS CodeDeploy** activa el despliegue gradual **`Canary10Percent5Minutes`** sobre el alias `live` de las Lambdas.<br>3. Actualiza el frontend en S3/CloudFront, corre `smoke-test.sh prod` y registra `DeploymentFrequency` y `LeadTimeMinutes` en CloudWatch. | [`Jenkinsfile`](../Jenkinsfile) (Líneas 184–206)<br>[`infra/template.yaml`](../infra/template.yaml)<br>[`infra/params/prod.json`](../infra/params/prod.json) | **🎯 P6 (Despliegue sin downtime y con rollback automático < 1 min)**.<br>**🎯 P4 (Métricas DORA en producción)**. | Si durante los 5 minutos del Canary se activa cualquiera de las **3 alarmas de CloudWatch**, **CodeDeploy hace rollback automático** a la versión anterior en segundos. |
| **Paso 9** | **`Bloque post { failure }: Diagnóstico Automático con IA (RCA)`** | Si **cualquier etapa (1 a 8)** falla, el bloque `post { failure }` registra `ChangeFailureCount=1` en CloudWatch y ejecuta `ai-devops-assistant.sh failure`, enviando el log sanitizado a **Amazon Bedrock (`nova-micro-v1:0`)** para obtener causa raíz y comando exacto de remediación. | [`Jenkinsfile`](../Jenkinsfile) (Líneas 215–227)<br>[`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh)<br>`reports/ai-failure-analysis.md` | **🎯 P4 (Diagnóstico rápido de incidentes — Reduce MTTR)** y **Entregable 6 (IA en DevOps)**. | Archiva `reports/ai-failure-analysis.md` en Jenkins listo para el ingeniero DevOps. |

---

### 8.2 Fase 2: Flujo Paso a Paso en Tiempo de Ejecución en AWS (`infra/template.yaml`)

| Paso | Capa en AWS | ¿Qué ocurre exactamente cuando un Agente usa la aplicación? | Recurso en `infra/template.yaml` | Problema(s) del PDF que Resuelve | Control de Seguridad / Resiliencia |
|---|---|---|---|---|---|
| **Paso 10** | **Entrada Perimetral y Entrega del Portal Web (SPA)** | El agente de seguros abre la URL HTTPS de **CloudFront**. En `prod`, **AWS WAFv2** inspecciona la petición contra reglas OWASP (`AWSManagedRulesCommonRuleSet`). CloudFront descarga el SPA desde `FrontendBucket` usando firma criptográfica **OAC (`SigV4`)**. | `FrontendWebACL`<br>`CloudFrontDistribution`<br>`CloudFrontOriginAccessControl`<br>`FrontendBucket` | **🎯 P7 (Datos sensibles y perímetro SFC):** Cifrado en tránsito (`TLS 1.2+`), mitigación de ataques web con WAF y bucket S3 100% privado. | `FrontendBucket` tiene las 4 banderas de `PublicAccessBlockConfiguration: true`; nadie puede acceder al S3 saltándose CloudFront. |
| **Paso 11** | **Autenticación y Enrutamiento en API Gateway** | Cuando el agente registra un siniestro (`POST /claims`) o solicita un PDF (`POST /documents`), la petición entra a **`SiniestrosApi` (API Gateway REST)** con trazabilidad **AWS X-Ray (`TracingEnabled: true`)** y control de acceso por **Amazon Cognito (`AgentsUserPool`)**. | `SiniestrosApi`<br>`AgentsUserPool`<br>`AgentsUserPoolClient` | **🎯 P4 (Trazabilidad End-to-End con X-Ray)**.<br>**🎯 P7 (Control de acceso autenticado para agentes)**. | Si la petición no es válida o supera límites, API Gateway la rechaza; si hay errores 5XX, alimenta la alarma `ApiGateway5xxAlarm`. |
| **Paso 12** | **Ejecución en Lambdas con Alias `live` y Secretos Dinámicos** | API Gateway invoca el alias `:live` de `ClaimsFunction` o `DocumentsFunction` (Node.js 22 `arm64`, `Tracing: Active`). La Lambda obtiene credenciales temporales de su rol IAM de mínimo privilegio y lee la configuración del secreto desde **AWS Secrets Manager** (`{{resolve:secretsmanager:...}}`). | `ClaimsFunction`<br>`DocumentsFunction`<br>`IntegrationSecret` | **🎯 P2 (Cero credenciales en código):** Usa Secrets Manager + roles IAM por función.<br>**🎯 P6 (Alias `:live` gestionado por CodeDeploy)**. | Ningún secreto existe en Git ni en texto plano en la plantilla; `IntegrationSecret` está cifrado con `AppKmsKey`. |
| **Paso 13** | **Almacenamiento Cifrado con KMS CMK y Resiliencia** | • `ClaimsFunction` guarda el siniestro en DynamoDB (`ClaimsTable`).<br>• `DocumentsFunction` guarda el reporte en S3 (`ReportsBucket`) y devuelve una **URL prefirmada temporal (5 min)**.<br>• Ambos recursos están cifrados en reposo con nuestra llave **`AppKmsKey` (`AWS::KMS::Key`)** con rotación anual automática. | `AppKmsKey`<br>`ClaimsTable`<br>`ReportsBucket` | **🎯 P7 (Cumplimiento SFC y Ley 1581 Habeas Data):** Cifrado KMS CMK, backups continuos y prevención de pérdida de datos. | • `ClaimsTable` tiene **PITR (35 días)** y `DeletionPolicy: Retain` en `prod`.<br>• `ReportsBucket` bloquea todo acceso público y expira objetos antiguos con `LifecycleConfiguration`. |
| **Paso 14** | **Logs en JSON y Enmascaramiento Nativo de PII en CloudWatch** | Las Lambdas tienen `LoggingConfig: LogFormat: JSON` forzado desde IaC. Antes de que CloudWatch escriba cualquier log en disco, el recurso **`ClaimsFunctionLogGroup`** ejecuta su **`DataProtectionPolicy` nativa**, detectando datos sensibles (como emails o llaves) y reemplazándolos por `*****`. | `Globals.Function.LoggingConfig`<br>`ClaimsFunctionLogGroup` (`DataProtectionPolicy`) | **🎯 P4 (Logs estructurados JSON para CloudWatch Insights)**.<br>**🎯 P7 (Protección de PII en logs 100% desde DevOps sin depender del backend)**. | En `prod`, los logs se conservan por **365 días** (`RetentionInDays: 365`) para auditorías de la SFC. |
| **Paso 15** | **Monitoreo Continuo, Alertas SNS y Auto-Rollback** | **CloudWatch** grafica la operación y las 4 métricas DORA en `ObservabilityDashboard` y evalúa cada 60 segundos las 3 alarmas (`ClaimsFunctionErrorsAlarm`, `DocumentsFunctionErrorsAlarm`, `ApiGateway5xxAlarm`). | `ObservabilityDashboard`<br>`ClaimsFunctionErrorsAlarm`<br>`DocumentsFunctionErrorsAlarm`<br>`ApiGateway5xxAlarm`<br>`AlertsTopic` | **🎯 P4 (Dashboards y alertas proactivas)**.<br>**🎯 P6 (Rollback automático en < 1 minuto)**. | Si `Errors >= 1` o `5XXError >= 2`:<br>1. Publica alerta inmediata en **Amazon SNS (`AlertsTopic`)**.<br>2. Si hay un despliegue en curso, **CodeDeploy aborta y regresa el tráfico a la versión anterior estable en segundos**. |

---

### 8.3 Tabla Resumen de Bolsillo (Los 7 Problemas vs. Solución DevOps)

| # | Problema del PDF | Solución Principal desde DevOps | Dónde está en el Flujo Integral |
|---|---|---|---|
| **P1** | **Despliegue manual** desde máquinas locales o consola | Pipeline declarativo de 8 etapas en `Jenkinsfile` con ruteo automático por rama (`dev`, `staging`, `prod`) y `sam deploy` sin intervención manual | **Fase 1:** `Pasos 1, 3, 6, 7 y 8` (`Jenkinsfile` + `samconfig.toml`) |
| **P2** | **Credenciales hardcodeadas** en archivos de configuración | **AWS Secrets Manager** (`IntegrationSecret` cifrado con KMS) + `{{resolve:secretsmanager:...}}` + Roles IAM de mínimo privilegio + **Gitleaks** | **Fase 1:** `Paso 4` (`Gitleaks`)<br>**Fase 2:** `Paso 12` (`Secrets Manager` + IAM) |
| **P3** | **Sin pruebas de seguridad** (SAST, SCA, IaC) antes de desplegar | `Stage 4` en paralelo (**Gitleaks + Semgrep + npm audit + Checkov**) + Quality Gate en `.security-exceptions.yaml` + Triage con **Bedrock** | **Fase 1:** `Pasos 4 y 5` (`Jenkinsfile` + `ai-devops-assistant.sh`) |
| **P4** | **Sin observabilidad** (sin dashboards, alertas ni trazabilidad) | **AWS X-Ray** activo + `LogFormat: JSON` + **3 CloudWatch Alarms → SNS** + `ObservabilityDashboard` con **4 métricas DORA** + **Bedrock RCA** | **Fase 1:** `Pasos 6, 8 y 9`<br>**Fase 2:** `Pasos 11, 14 y 15` |
| **P5** | **Configuración inconsistente** editada manualmente sin validación | Archivos parametrizados `infra/params/{dev,staging,prod}.json` validados antes de desplegar con **JSON Schema (`schema.json`)** + `validate-params.sh` + `sam validate` | **Fase 1:** `Paso 2` (`Stage 2` del `Jenkinsfile`) |
| **P6** | **Sin estrategia de rollback** (manual y tarda > 1 hora) | `AutoPublishAlias: live` + **AWS CodeDeploy (`Canary10Percent5Minutes`)** conectado a las 3 alarmas de CloudWatch para **Auto-Rollback en < 1 minuto** | **Fase 1:** `Paso 8`<br>**Fase 2:** `Pasos 12 y 15` |
| **P7** | **Datos sensibles (PII)** y regulación **SFC** | **KMS CMK (`AppKmsKey`)** con rotación anual + **CloudWatch `DataProtectionPolicy` (`*****`)** + **S3 privado con OAC** + **WAFv2 + Cognito** + **DynamoDB PITR** + **365 días de logs** | **Fase 1:** `Pasos 2, 4 y 7`<br>**Fase 2:** `Pasos 10, 11, 13 y 14` |



