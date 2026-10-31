# Mapeo Oficial: Arquitectura, Componentes, Funciones Lambda, Endpoints y Ambientes

Este documento resume la correspondencia exacta **1 a 1** entre lo solicitado en el PDF de la prueba técnica, el diagrama de arquitectura y los recursos implementados en el repositorio.

---

## 1. Componentes Desplegados (Arquitectura en `infra/template.yaml`)

| Capa | Servicio (PDF) | Detalle (PDF) | Recurso Implementado en [`infra/template.yaml`](../infra/template.yaml) |
|---|---|---|---|
| **CDN** | **CloudFront** | Distribución con certificado ACM y WAF | • `CloudFrontDistribution` (`AWS::CloudFront::Distribution`)<br>• `FrontendWebACL` (`AWS::WAFv2::WebACL` condicional)<br>• `CustomDomainCertificateArn` (ACM o certificado por defecto de CloudFront) |
| **Frontend** | **S3 Bucket** | Aplicación SPA | • `FrontendBucket` (`siniestros-${Env}-frontend-${AccountId}`)<br>• `CloudFrontOriginAccessControl` (OAC SigV4)<br>• Código en [`frontend/index.html`](../frontend/index.html) |
| **API** | **API Gateway** | Endpoints REST | • `SiniestrosApi` (`AWS::Serverless::Api` — `siniestros-${Env}-api`)<br>• `AgentsUserPool` (`AWS::Cognito::UserPool` para autenticación JWT) |
| **Compute** | **Lambda (`arm64`)** | 2 funciones de negocio | • `ClaimsFunction` (`siniestros-${Env}-claims`)<br>• `DocumentsFunction` (`siniestros-${Env}-documents`)<br>• Ambas en `nodejs22.x`, arquitectura **`arm64`** y `AutoPublishAlias: live` (CodeDeploy) |
| **Data** | **DynamoDB + S3 Documentos** | Tabla de siniestros (on-demand) + Almacenamiento de reportes PDF | • `ClaimsTable` (`siniestros-${Env}-claims` en modo `PAY_PER_REQUEST` + `PITR`)<br>• `ReportsBucket` (`siniestros-${Env}-reports-${AccountId}` cifrado con KMS para guardar los PDFs) |
| **Seguridad** | **Secrets Manager + KMS** | Credenciales de integraciones y cifrado PII (SFC) | • `IntegrationSecret` (`AWS::SecretsManager::Secret`)<br>• `AppKmsKey` (`AWS::KMS::Key` con rotación anual automática) |
| **Observabilidad** | **CloudWatch + SNS + X-Ray** | Logs, métricas DORA, trazas y alertas de rollback | • `ClaimsFunctionErrorsAlarm`, `DocumentsFunctionErrorsAlarm`, `ApiGateway5xxAlarm`<br>• `ObservabilityDashboard` (`siniestros-${Env}-operations-dora`)<br>• `AlertsTopic` (`AWS::SNS::Topic`) + `Tracing: Active` (X-Ray) |
| **IaC** | **CloudFormation (SAM)** | Template parametrizado por ambiente | • [`infra/template.yaml`](../infra/template.yaml)<br>• [`infra/samconfig.toml`](../infra/samconfig.toml)<br>• [`infra/params/dev.json`](../infra/params/dev.json), [`staging.json`](../infra/params/staging.json), [`prod.json`](../infra/params/prod.json) |

---

## 2. Funciones Lambda y Endpoints REST

### 2.1 Funciones Lambda
| Función | Archivo en el Proyecto | Responsabilidad |
|---|---|---|
| **`claims`** | [`backend/claims/index.mjs`](../backend/claims/index.mjs) | Registro, consulta y actualización de siniestros vehiculares en DynamoDB, lectura de credenciales en Secrets Manager y enmascaramiento de PII (`maskPii()`) en CloudWatch Logs. |
| **`documents`** | [`backend/documents/index.mjs`](../backend/documents/index.mjs) | Consulta del siniestro en DynamoDB, generación del reporte oficial en formato **PDF**, almacenamiento cifrado con KMS en S3 (`ReportsBucket`) y entrega de URL prefirmada temporal (5 minutos). |

### 2.2 Endpoints en API Gateway
| Método | Path | Función Lambda | Descripción Funcional |
|---|---|---|---|
| **`POST`** | `/api/v1/claims` | `claims` | Registra un nuevo siniestro vehicular (`status: REGISTERED`) y oculta cédula/nombre/teléfono en los logs (Cumplimiento SFC / Ley 1581). |
| **`GET`** | `/api/v1/claims/{id}` | `claims` | Consulta el detalle completo de un siniestro por su `claimId`. |
| **`PATCH`** | `/api/v1/claims/{id}` | `claims` | Actualiza el estado (`IN_REVIEW`, `APPROVED`, `REJECTED`, `CLOSED`) y las notas del ajustador. |
| **`POST`** | `/api/v1/documents/report` | `documents` | Genera el PDF del siniestro, lo guarda en S3 con cifrado KMS y devuelve `downloadUrl` (URL prefirmada válida por 300 segundos). |

---

## 3. Ambientes Configurados (`dev`, `staging`, `prod`)

Definidos en [`infra/params/`](../infra/params/) y [`infra/samconfig.toml`](../infra/samconfig.toml), y validados automáticamente con [`infra/params/schema.json`](../infra/params/schema.json):

| Ambiente | Propósito | Stack en AWS | Archivo de Parámetros | Configuración Diferenciada |
|---|---|---|---|---|
| **`dev`** | Desarrollo y pruebas unitarias | `siniestros-dev` | [`infra/params/dev.json`](../infra/params/dev.json) | • **Memoria / Timeout Lambda:** `256 MB` / `15 s`<br>• **Estrategia CodeDeploy:** `AllAtOnce` (despliegue inmediato)<br>• **AWS WAFv2:** `false` (optimización de costos)<br>• **Retención de Logs:** `14 días`<br>• **Política de Borrado DynamoDB:** `Delete` |
| **`staging`** | QA y pruebas de integración | `siniestros-staging` | [`infra/params/staging.json`](../infra/params/staging.json) | • **Memoria / Timeout Lambda:** `256 MB` / `20 s`<br>• **Estrategia CodeDeploy:** `Linear10PercentEvery1Minute`<br>• **AWS WAFv2:** `false`<br>• **Retención de Logs:** `30 días`<br>• **Política de Borrado DynamoDB:** `Delete` |
| **`prod`** | Producción (Regulado SFC) | `siniestros-prod` | [`infra/params/prod.json`](../infra/params/prod.json) | • **Memoria / Timeout Lambda:** `512 MB` / `25 s`<br>• **Estrategia CodeDeploy:** **`Canary10Percent5Minutes`** (con Auto-Rollback por alarmas)<br>• **AWS WAFv2:** **`true`** (protección OWASP activa)<br>• **Retención de Logs:** **`365 días`** (Auditoría SFC)<br>• **Política de Borrado DynamoDB:** **`Retain`** (protección de datos productivos) |

