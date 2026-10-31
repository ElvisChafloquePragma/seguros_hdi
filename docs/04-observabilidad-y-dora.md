# Entregable 5: Observabilidad, Alertas Críticas y Métricas DORA

> **Requisitos del PDF:**
> - *Proponer stack de monitoreo para la aplicación*
> - *Definir alertas críticas*
> - *¿Cómo medir métricas DORA?*

---

## 1. Stack de Monitoreo Propuesto e Implementado (100% desde IaC / DevOps)

Toda la observabilidad está definida como código en [`infra/template.yaml`](../infra/template.yaml) (sin depender de agentes de terceros ni del código de los desarrolladores backend):

| Pilar de Observabilidad | Servicio AWS Implementado | Cómo está configurado en [`infra/template.yaml`](../infra/template.yaml) | Qué problema resuelve |
|---|---|---|---|
| **1. Logs Estructurados en JSON + Protección de PII** | **Amazon CloudWatch Logs** (`ClaimsFunctionLogGroup`) | • En `Globals.Function`: `LoggingConfig: LogFormat: JSON` (fuerza desde AWS que todos los logs de las Lambdas se estructuren en JSON con `timestamp`, `level`, `requestId`).<br>• En `ClaimsFunctionLogGroup`: **`DataProtectionPolicy` nativa** que enmascara datos sensibles con `*****` antes de guardarlos en disco + retención parametrizada (`365 días` en `prod`). | Permite filtrar incidentes en segundos con **CloudWatch Logs Insights** y garantiza que ningún dato PII quede expuesto en texto plano. |
| **2. Trazabilidad Distribuida End-to-End** | **AWS X-Ray** | • En `Globals.Function`: `Tracing: Active` ([L65](../infra/template.yaml#L65)).<br>• En `SiniestrosApi`: `TracingEnabled: true` ([L183](../infra/template.yaml#L183)). | Genera automáticamente el **Service Map** (`API Gateway → Lambda → DynamoDB / S3 / Secrets Manager`) mostrando en qué salto exacto ocurre una latencia o error. |
| **3. Tablero Unificado de Operaciones y DORA** | **Amazon CloudWatch Dashboard** (`ObservabilityDashboard`) | Crea automáticamente el dashboard `siniestros-${Env}-operations-dora` ([L477–535](../infra/template.yaml#L477-L535)) con 3 paneles: (1) Peticiones y errores `5XX` en API Gateway, (2) Invocaciones y errores en `claims` y `documents`, y (3) Las **4 Métricas DORA**. | Elimina la revisión a ciegas de logs al centralizar la salud técnica y el desempeño de despliegues en una sola pantalla. |
| **4. Alertamiento y Auto-Remediación** | **CloudWatch Alarms + Amazon SNS (`AlertsTopic`) + AWS CodeDeploy** | 3 alarmas críticas ([L420–475](../infra/template.yaml#L420-L475)) conectadas simultáneamente al tópico SNS `AlertsTopic` y al bloque `DeploymentPreference.Alarms` de CodeDeploy. | Notifica al equipo en tiempo real y ejecuta **Rollback Automático en < 1 minuto** si un despliegue introduce errores. |

---

## 2. Alertas Críticas Definidas en [`infra/template.yaml`](../infra/template.yaml)

Definimos **3 alarmas críticas de alta sensibilidad (`Period: 60 segundos`, `TreatMissingData: notBreaching`)**:

| Alarma en `infra/template.yaml` | Namespace y Métrica Vigilada | Condición de Disparo | Acción Automática 1 (Notificación) | Acción Automática 2 (Auto-Rollback) |
|---|---|---|---|---|
| **`ClaimsFunctionErrorsAlarm`** ([L425–440](../infra/template.yaml#L425-L440)) | `AWS/Lambda` → `Errors`<br>(`FunctionName: siniestros-${Env}-claims`) | `Sum >= 1` error en 1 minuto | Publica alerta inmediata en **Amazon SNS (`AlertsTopic`)** | **AWS CodeDeploy aborta el Canary y revierte el alias `:live` de `claims` a la versión anterior estable** |
| **`DocumentsFunctionErrorsAlarm`** ([L442–457](../infra/template.yaml#L442-L457)) | `AWS/Lambda` → `Errors`<br>(`FunctionName: siniestros-${Env}-documents`) | `Sum >= 1` error en 1 minuto | Publica alerta inmediata en **Amazon SNS (`AlertsTopic`)** | **AWS CodeDeploy aborta el Canary y revierte el alias `:live` de `documents` a la versión anterior estable** |
| **`ApiGateway5xxAlarm`** ([L459–475](../infra/template.yaml#L459-L475)) | `AWS/ApiGateway` → `5XXError`<br>(`ApiName: siniestros-${Env}-api`) | `Sum >= 2` errores `5XX` en 1 minuto | Publica alerta inmediata en **Amazon SNS (`AlertsTopic`)** | **AWS CodeDeploy aborta el despliegue activo en ambas Lambdas y regresa a la versión estable previa** |

---

## 3. ¿Cómo medir las 4 Métricas DORA?

Automatizamos la medición y publicación de las **4 métricas DORA** mediante el script [`scripts/dora-metrics.sh`](../scripts/dora-metrics.sh), que es invocado automáticamente en las **Etapas 5, 6 y 8** (despliegues exitosos) y en el bloque **`post { failure }`** del [`Jenkinsfile`](../Jenkinsfile), enviando las métricas con `aws cloudwatch put-metric-data` al namespace personalizado **`SiniestrosDORA`**:

| Métrica DORA | Nombre en CloudWatch (`SiniestrosDORA`) | Cómo la calcula [`scripts/dora-metrics.sh`](../scripts/dora-metrics.sh) | Cómo se visualiza en `ObservabilityDashboard` |
|---|---|---|---|
| **1. Deployment Frequency (DF)** *(Frecuencia de Despliegue)* | `DeploymentFrequency` (`Unit: Count`) | Cada vez que termina un despliegue en `Stage 5 (dev)`, `Stage 6 (staging)` o `Stage 8 (prod)`, publica `Value = 1` con la dimensión `Environment=${ENV}`. | Suma total (`Sum`) de despliegues realizados por día/semana en cada ambiente. |
| **2. Lead Time for Changes (LT)** *(Tiempo de Entrega de Cambios)* | `LeadTimeMinutes` (`Unit: Count`) | Resta el timestamp actual (`date +%s`) menos el timestamp exacto del commit en Git (`git log -1 --format=%ct`) dividido entre 60: `((NOW_EPOCH - COMMIT_EPOCH) / 60)`. | Promedio (`Average`) de minutos que tarda un commit desde que se escribe hasta que corre en producción. |
| **3. Change Failure Rate (CFR)** *(Tasa de Fallo por Cambio)* | `ChangeFailureCount` (`Unit: Count`) | • Si el despliegue y `smoke-test.sh` pasan en verde: publica `Value = 0`.<br>• Si cualquier etapa o smoke test falla (o salta un rollback): el bloque `post { failure }` publica `Value = 1`. | Permite calcular el porcentaje exacto de despliegues fallidos (`Sum(ChangeFailureCount) / Sum(DeploymentFrequency)`). |
| **4. Mean Time to Restore (MTTR)** *(Tiempo Medio de Recuperación)* | `MeanTimeToRestoreMinutes` (`Unit: Count`) | Registra los minutos transcurridos para restaurar el servicio ante un fallo o rollback automático de CodeDeploy (pasando de **> 60 min** manuales a **< 2 min** automatizados). | Promedio (`Average`) del tiempo de recuperación en el panel DORA de CloudWatch. |

---

## 4. Guion Corto para Sustentar el Entregable 5 en la Entrevista (30 segundos)
> *"Para el Entregable 5 implementamos en `infra/template.yaml` un stack de observabilidad 100% nativo en AWS: forzamos logs estructurados en JSON (`LoggingConfig: LogFormat: JSON`) con `DataProtectionPolicy` en CloudWatch Logs, activamos **AWS X-Ray** (`Tracing: Active`) entre API Gateway y las Lambdas para trazabilidad end-to-end, y creamos el tablero `ObservabilityDashboard`. Definimos **3 alarmas críticas** (`ClaimsFunctionErrorsAlarm`, `DocumentsFunctionErrorsAlarm` y `ApiGateway5xxAlarm`) que notifican a **SNS** y disparan el **Auto-Rollback en CodeDeploy**. Finalmente, medimos las **4 métricas DORA** con `scripts/dora-metrics.sh` desde el `Jenkinsfile`, publicando `DeploymentFrequency`, `LeadTimeMinutes` (calculado desde el timestamp del commit en Git), `ChangeFailureCount` y `MeanTimeToRestoreMinutes` en el namespace `SiniestrosDORA` de CloudWatch."*
