# Entregable 6: Integración de Inteligencia Artificial (AI) en el Flujo DevOps

> **Requisito del PDF:**
> - *Proponer al menos 2 casos de uso de AI aplicados al flujo DevOps de esta aplicación*

---

## 1. ¿Por qué elegimos Amazon Bedrock (`amazon.nova-micro-v1:0`) para una Aseguradora Regulada por la SFC?

En una entidad vigilada por la **Superintendencia Financiera de Colombia (SFC)**, enviar logs de infraestructura o reportes de vulnerabilidades a APIs públicas externas fuera del perímetro de la nube incumple la **Circular Externa 005 de 2019 (Riesgos en Computación en la Nube)**. Por eso implementamos la integración con **Amazon Bedrock** dentro de la misma cuenta de AWS (`us-east-1`):

| Criterio Técnico / Regulatorio | Cómo lo cumple nuestra implementación en [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) |
|---|---|
| **1. Soberanía y Privacidad de Datos (SFC)** | La invocación (`aws bedrock-runtime converse`) ocurre dentro de la misma cuenta de AWS (`us-east-1`); Amazon Bedrock no almacena prompts ni los utiliza para entrenar modelos públicos. El modelo se parametriza con `BEDROCK_MODEL_ID` (por defecto `amazon.nova-micro-v1:0`). |
| **2. Sanitización Previa de PII (`sanitize_pii`)** | Antes de armar el payload hacia Bedrock, un filtro regex enmascara cédulas (`[REDACTED_ID]`), correos (`[REDACTED_EMAIL]`) y llaves de acceso AWS (`[REDACTED_AWS_KEY]`). |
| **3. Resiliencia / Fail-Safe sin Aprobaciones Falsas** | Si el servicio de IA no está disponible o falla la red, el script genera un dictamen de advertencia indicando la indisponibilidad de la IA para que el aprobador humano inspeccione los JSON crudos; **nunca inventa o finge una aprobación de seguridad**, garantizando cumplimiento estricto ante la SFC. |
| **4. Costo Casi Cero (`<$0.0001 USD` por ejecución)** | El modelo `amazon.nova-micro-v1:0` cuesta `US$0.035` por millón de tokens de entrada; cada corrida del pipeline consume ~400 tokens. |

---

## 2. Los 3 Casos de Uso de AI Implementados en Nuestro Proyecto (CI/CD + AWS Runtime)

El PDF pide al menos 2 casos de uso; nosotros **implementamos 3 casos de uso reales en código** (2 en el pipeline [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) y 1 en vivo en AWS mediante [`backend/incident-ai/index.mjs`](../backend/incident-ai/index.mjs) + [`infra/template.yaml`](../infra/template.yaml)):

| Aspecto | Caso de Uso #1 (Implementado en CI/CD):<br>**Triage Inteligente de Seguridad DevSecOps para Aprobación de PROD** | Caso de Uso #2 (Implementado en CI/CD):<br>**Diagnóstico Automático de Causa Raíz (RCA) ante Fallos del Pipeline** | Caso de Uso #3 (Implementado en AWS Runtime):<br>**ChatOps de Incidentes en Vivo (`Alarm → SNS → Lambda + Bedrock → SNS ChatOps`)** |
|---|---|---|---|
| **Dónde actúa** | **`Stage 4: Security Scan` → `post { always }`** ([L116–125](../Jenkinsfile#L116-L125)) y **`Stage 7: Manual Approval`** ([L186–187](../Jenkinsfile#L186-L187)). | **Bloque global `post { failure }`** del [`Jenkinsfile`](../Jenkinsfile#L237-L250). | **En vivo en AWS (`infra/template.yaml`):** `Claims/Documents/ApiGw Alarm` → `AlertsTopic` → Lambda `IncidentAiFunction` → `ChatOpsSummaryTopic`. |
| **Archivo / Comando** | `bash scripts/ai-devops-assistant.sh triage reports/combined-security.txt reports/security-summary.md` | `bash scripts/ai-devops-assistant.sh failure reports/combined-security.txt reports/ai-failure-analysis.md` | [`backend/incident-ai/index.mjs`](../backend/incident-ai/index.mjs) suscrita a `AlertsTopic` y publicando en `ChatOpsSummaryTopic`. |
| **Qué problema DevOps resuelve** | Los 4 escáneres (**Gitleaks, Semgrep, npm audit y Checkov**) generan archivos JSON extensos que un aprobador humano tarda mucho en correlacionar antes de autorizar `prod`. | Cuando falla un despliegue en CloudFormation o un smoke test, buscar la causa raíz entre cientos de líneas de log eleva el **MTTR**. | Cuando salta una alarma en producción, el ingeniero de guardia pierde minutos valiosos entrando a CloudWatch Logs para entender qué causó el error y el rollback. |
| **Qué hace exactamente con Amazon Bedrock** | Extrae de forma estructurada los fallos de Checkov con Python, sanitiza PII y pide a `nova-micro-v1:0` un dictamen ejecutivo evaluando el Quality Gate y riesgos SFC. | Toma las últimas líneas sanitizadas del fallo y pide a `nova-micro-v1:0` la causa raíz exacta y el comando de remediación. | Filtra transiciones `ALARM` (ignorando `OK` por FinOps), consulta los últimos 10 min de logs con `FilterLogEvents`, **sanitiza PII (`sanitizeLogText`)**, invoca a **Bedrock (`nova-micro-v1:0`)** y publica el RCA en un **segundo tópico SNS (`ChatOpsSummaryTopic`)** evitando bucles infinitos. |
| **Artefacto / Salida** | `reports/security-summary.md` (impreso en consola antes del botón `Aprobar y Desplegar a PROD`). | `reports/ai-failure-analysis.md` (archivado en Jenkins junto con el registro `FAILURE` en DORA). | Notificación ejecutiva en `siniestros-<env>-chatops-summary` (lista para **Email SRE** o **AWS Chatbot en Slack / Microsoft Teams** con costo `$0.00` en Free Tier). |

---

## 3. Caso Adicional Propuesto (Roadmap DevOps)

| Caso Adicional Propuesto | Flujo Técnico en AWS | Beneficio en Métricas DORA |
|---|---|---|
| **Caso #4: Revisión Preventiva de IaC y Costos FinOps en Pull Requests** | Antes de hacer merge a `main`, un hook analiza el `git diff` de `infra/template.yaml` con **Bedrock** para advertir si un cambio introduce recursos con cobro fijo alto (ej. NAT Gateways) o permisos IAM excesivos (`Action: "*"`). | Reduce el **Change Failure Rate (CFR)** y protege el presupuesto Cloud. |

---

## 4. Guion Corto para Sustentar el Entregable 6 en la Entrevista (30 segundos)
> *"Para el Entregable 6 superamos los 2 casos solicitados e implementamos **3 casos de uso reales en código** conectados a **Amazon Bedrock (`amazon.nova-micro-v1:0`)** dentro de la misma cuenta de AWS y con sanitización previa de PII para cumplir con la SFC:
> 1) **Triage Inteligente DevSecOps (`modo triage` en Jenkins):** consolida los reportes de Gitleaks, Semgrep, npm audit y Checkov y genera `reports/security-summary.md` para el aprobador de producción.
> 2) **Diagnóstico Automático de Fallos del Pipeline (`modo failure` en Jenkins):** si falla cualquier etapa, analiza el log sanitizado con Bedrock y entrega la causa raíz y comando de remediación en `reports/ai-failure-analysis.md`.
> 3) **ChatOps de Incidentes en Vivo (`IncidentAiFunction` en AWS):** cuando una alarma de CloudWatch salta a `ALARM` y dispara `AlertsTopic`, nuestra tercera Lambda lee los últimos logs de error en CloudWatch, enmascara PII, consulta a Bedrock y publica el diagnóstico de causa raíz en un segundo tópico SNS (`ChatOpsSummaryTopic`, evitando bucles infinitos) hacia Correo o Slack/Teams con costo `$0.00` en Free Tier."*

