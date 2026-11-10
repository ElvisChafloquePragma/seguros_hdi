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

## 2. Los 2 Casos de Uso de AI Implementados en Nuestro Proyecto

Ambos casos de uso están programados en [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) e integrados directamente en el [`Jenkinsfile`](../Jenkinsfile):

| Aspecto | Caso de Uso #1 (Implementado):<br>**Triage Inteligente de Seguridad DevSecOps para Aprobación de Producción** | Caso de Uso #2 (Implementado):<br>**Diagnóstico Automático de Causa Raíz (RCA) ante Fallos del Pipeline o Rollbacks** |
|---|---|---|
| **Dónde actúa en el [`Jenkinsfile`](../Jenkinsfile)** | **`Stage 4: Security Scan` → bloque `post { always }`** ([L116–125](../Jenkinsfile#L116-L125)) y se muestra en **`Stage 7: Manual Approval`** ([L186–187](../Jenkinsfile#L186-L187)). | **Bloque global `post { failure }`** del pipeline ([L237–250](../Jenkinsfile#L237-L250)). |
| **Comando ejecutado** | `bash scripts/ai-devops-assistant.sh triage reports/combined-security.txt reports/security-summary.md` | `bash scripts/ai-devops-assistant.sh failure reports/combined-security.txt reports/ai-failure-analysis.md` |
| **Qué problema DevOps resuelve** | Los 4 escáneres (**Gitleaks, Semgrep, npm audit y Checkov**) generan archivos JSON extensos que un aprobador humano tarda mucho en correlacionar antes de autorizar el paso a producción (`Stage 7`). | Cuando falla un despliegue en CloudFormation, un smoke test o se dispara un rollback en CodeDeploy, buscar la causa raíz entre cientos de líneas de log eleva el **MTTR**. |
| **Qué hace exactamente con Amazon Bedrock** | Extrae de forma estructurada los fallos de Checkov con un parser dinámico en Python (sin truncar), sanitiza PII y pide a `nova-micro-v1:0` un dictamen ejecutivo evaluando: (1) Estado del Quality Gate (`APROBADO` / `BLOQUEADO`), (2) Riesgos sobre datos PII bajo normativa SFC, y (3) Recomendación para el aprobador de `prod`. | Toma las últimas líneas sanitizadas del fallo y pide a `nova-micro-v1:0`: (1) Causa raíz exacta del error en CloudFormation/SAM/Pipeline, (2) Comando o cambio exacto en YAML para corregirlo, y (3) Impacto en **MTTR**. |
| **Artefacto generado** | `reports/security-summary.md` (impreso en la consola de Jenkins justo antes del botón `Aprobar y Desplegar a PROD`). | `reports/ai-failure-analysis.md` (archivado en Jenkins junto con el registro `FAILURE` en las métricas DORA). |

---

## 3. Casos de Uso Adicionales Propuestos (Evolución DevOps)

Además de los 2 casos implementados en código, proponemos 2 casos adicionales para el roadmap de la aseguradora:

| Caso Adicional Propuesto | Flujo Técnico en AWS | Beneficio en Métricas DORA |
|---|---|---|
| **Caso #3: ChatOps de Incidentes en Vivo (`CloudWatch Alarm → SNS → AWS Chatbot / Bedrock`)** | Cuando salta `ClaimsFunctionErrorsAlarm` o `ApiGateway5xxAlarm` en producción, el tópico `AlertsTopic` notifica directamente a Correo o Slack/Teams vía **AWS Chatbot** (con Amazon Q / Bedrock resumiendo los últimos 5 minutos de logs y trazas de X-Ray). | Reduce el **MTTR** de diagnóstico en producción a menos de **15 segundos** con costo `$0.00` en Free Tier. |
| **Caso #4: Revisión Preventiva de IaC y Costos FinOps en Pull Requests** | Antes de hacer merge a `main`, un hook analiza el `git diff` de `infra/template.yaml` con **Bedrock** para advertir si un cambio introduce recursos con cobro fijo alto (ej. NAT Gateways) o permisos IAM excesivos (`Action: "*"`). | Reduce el **Change Failure Rate (CFR)** y protege el presupuesto Cloud. |

---

## 4. Guion Corto para Sustentar el Entregable 6 en la Entrevista (30 segundos)
> *"Para el Entregable 6 implementamos 2 casos de uso reales en `scripts/ai-devops-assistant.sh` conectados a **Amazon Bedrock (`amazon.nova-micro-v1:0`)** dentro de la misma cuenta de AWS y con sanitización previa de PII (`sanitize_pii`) para cumplir con la SFC:
> 1) **Triage Inteligente DevSecOps (`modo triage`):** al terminar la Etapa 4 del `Jenkinsfile`, consolida los reportes de Gitleaks, Semgrep, npm audit y Checkov y genera `reports/security-summary.md`, el cual se presenta al aprobador en la Etapa 7 antes de autorizar el paso a producción.
> 2) **Diagnóstico Automático de Causa Raíz (`modo failure`):** en el bloque `post { failure }` del `Jenkinsfile`, si falla cualquier etapa o despliegue, analiza el log sanitizado con Bedrock y entrega la causa raíz y el comando exacto de remediación en `reports/ai-failure-analysis.md`, reduciendo drásticamente el MTTR."*

