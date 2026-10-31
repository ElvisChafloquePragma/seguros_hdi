# Entregable Transversal: Análisis de Costos y Operación (FinOps)

## 1. Estrategia de Costos Mínimos (Free Tier + Despliegue Eficiente)

Siguiendo las restricciones del caso práctico (*preferir servicios serverless/managed y aprovechar AWS Free Tier*), toda la arquitectura en [`infra/template.yaml`](../infra/template.yaml) está optimizada para operar con costo cercano a **US\$0.00**:

| Servicio AWS | Configuración en `infra/template.yaml` | Costo en `dev` (Demostración) | Costo en `prod` (si se activa por 2–3 días) |
|---|---|---|---|
| **AWS Lambda (`arm64`)** | Funciones `claims` y `documents` sobre Graviton2 (`arm64`, 20% más económico) y sin dependencias pesadas. | **US\$0.00** (Free Tier: 1M invocaciones/mes) | **US\$0.00** |
| **Amazon API Gateway REST** | Stage por ambiente (`/dev`, `/staging`, `/prod`). | **US\$0.00** (Free Tier: 1M llamadas/mes) | **US\$0.00** |
| **Amazon DynamoDB** | `BillingMode: PAY_PER_REQUEST` (On-Demand). | **US\$0.00** (Free Tier: 25 GB + 200M req) | **US\$0.00** |
| **Amazon S3 + CloudFront** | `FrontendBucket` + `ReportsBucket` + `CloudFrontDistribution` (`PriceClass_100`). | **US\$0.00** (Free Tier: 5 GB S3 + 1 TB CF + 1,000 invalidaciones) | **US\$0.00** |
| **Amazon Cognito** | `AgentsUserPool` para autenticación JWT. | **US\$0.00** (Free Tier perpetuo hasta 50,000 MAU) | **US\$0.00** |
| **AWS Secrets Manager** | `IntegrationSecret` autogenerado. | **US\$0.00** (30 días de prueba gratuita) | **US\$0.00** |
| **AWS KMS (`AppKmsKey`)** | Llave CMK con rotación anual para cifrar PII (SFC). | **~US\$0.10 – US\$1.00** (prorrateado; se elimina con `teardown.sh`) | **~US\$0.10 – US\$1.00** |
| **AWS WAFv2 (`FrontendWebACL`)** | Condición `ShouldEnableWaf`: **apagado en `dev` y `staging` (`EnableWaf=false`)** y encendido solo en `prod` (prorrateado por hora a ~US\$0.008/h). | **US\$0.00** (`EnableWaf=false`) | **~US\$0.55** (por 72 horas activo) |
| **Amazon Bedrock (`nova-micro-v1:0`)** | Usado en [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) (~US\$0.00007 por ejecución). | **< US\$0.01** | **< US\$0.01** |
| **CloudWatch Logs, Alarms & Dashboard** | 3 alarmas + 1 dashboard (dentro del límite gratuito de 10 alarmas y 3 dashboards). | **US\$0.00** | **US\$0.00** |
| **TOTAL ESTIMADO** | | **~US\$0.10 – US\$1.00 USD** | **~US\$1.15 – US\$1.60 USD** |

---

## 2. Limpieza Automatizada de Recursos (`scripts/teardown.sh`)

El script [`scripts/teardown.sh`](../scripts/teardown.sh) vacía automáticamente los buckets S3 versionados (`frontend` y `reports`) y elimina los stacks de CloudFormation para no dejar ningún recurso activo tras la sustentación:

```bash
bash scripts/teardown.sh
```
