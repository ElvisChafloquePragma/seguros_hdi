# Entregable 4: Seguridad Integrada (DevSecOps) y Regulación SFC

> **Requisitos del PDF:**
> - *¿Qué herramientas integrar en el pipeline?*
> - *¿Cómo manejar vulnerabilidades detectadas (bloqueo vs advertencia)?*
> - *¿Cómo cumplir con regulación SFC para datos de asegurados?*

---

## 1. ¿Qué herramientas integrar en el pipeline?

En las **Etapas 2 y 4** del [`Jenkinsfile`](../Jenkinsfile) integramos **5 herramientas automatizadas** que cubren todas las capas de seguridad (**Secretos + SAST + SCA + IaC + Triage con IA**):

| Categoría DevSecOps | Herramienta Integrada | Etapa del `Jenkinsfile` | Comando Ejecutado | Qué verifica exactamente | Evidencia en `reports/` |
|---|---|---|---|---|---|
| **1. Escaneo de Secretos** | **Gitleaks** | `Stage 4a` (Paralelo) | `gitleaks detect --source=. --no-git --redact` | Busca llaves AWS (`AKIA...`), contraseñas, tokens JWT o llaves privadas en todo el repositorio. **Bloquea** si encuentra alguno. | `reports/gitleaks-all.json` |
| **2. Análisis Estático de Código (SAST)** | **Semgrep** | `Stage 4b` (Paralelo) | `semgrep scan --config p/owasp-top-ten --metrics=off --error backend/claims backend/documents` | Analiza el código JavaScript de las Lambdas contra el ruleset OWASP Top 10, sin enviar telemetría. **Bloquea** si hay hallazgos. | `reports/semgrep-sast.json` |
| **3. Análisis de Dependencias (SCA)** | **npm audit** | `Stage 4c` (Paralelo) | `npm audit --audit-level=high --json` | Revisa `package-lock.json` buscando CVE. **Bloquea** solo con severidad `HIGH` o `CRITICAL`. | `reports/npm-audit-backend.json` |
| **4. Seguridad de Infraestructura (IaC Scan)** | **Checkov + `sam validate` + `check-jsonschema`** | `Stage 2` y `Stage 4d` (Paralelo) | `checkov -f infra/template.yaml --framework cloudformation --hard-fail-on CKV_AWS_7,CKV_AWS_19,CKV_AWS_20,CKV_AWS_26,CKV_AWS_28,CKV_AWS_33,CKV_AWS_45,CKV_AWS_53,CKV_AWS_54,CKV_AWS_55,CKV_AWS_56,CKV_AWS_57,CKV_AWS_119,CKV_AWS_149,CKV_AWS_158,CKV_AWS_173 -o json > reports/checkov-iac.json` | Audita `infra/template.yaml`. **Bloquean 16 checks críticos** (cifrado KMS CMK en DynamoDB/SNS/Logs/Lambda, S3 privado, rotación KMS, PITR, IAM); los hallazgos restantes se reportan completos en el JSON y Bedrock los analiza. | `reports/checkov-iac.json` |
| **5. Triage Inteligente con IA** | **Amazon Bedrock (`BEDROCK_MODEL_ID`, por defecto `amazon.nova-micro-v1:0`)** | `Stage 4 -> post { always }` | `bash scripts/ai-devops-assistant.sh triage` | Consolida los reportes y genera un dictamen en Markdown. Es **asesor**: si Bedrock no responde, el dictamen lo dice y exige revisión manual (nunca simula una aprobación). | `reports/security-summary.md` |

> **Fail-closed:** las herramientas vienen preinstaladas en la imagen del runner ([`ci/jenkins/Dockerfile`](../ci/jenkins/Dockerfile)). Si una falta, el stage falla; ya no existe el reporte simulado `skipped_tool_missing`.

---

## 2. ¿Cómo manejar vulnerabilidades detectadas (Bloqueo vs. Advertencia)?

Definimos una política formal de **Quality Gates** versionada como código en [`.security-exceptions.yaml`](../.security-exceptions.yaml) que separa claramente qué hallazgos **rompen el build inmediatamente** y cuáles generan **advertencia con SLA de remediación**:

| Tipo de Hallazgo / Severidad | Acción en el Pipeline (`Jenkinsfile`) | SLA Máximo de Remediación | Justificación Operativa y de Gobierno |
|---|---|---|---|
| **Secreto o Credencial Expuesta (Gitleaks)** | ❌ **BLOQUEO INMEDIATO (`exit 1`)** + rotación inmediata del secreto | **Inmediato (0 días)** | Ninguna credencial puede llegar al repositorio ni a los artefactos bajo ninguna circunstancia. |
| **Vulnerabilidad `CRITICAL` o `HIGH` con parche disponible (SAST / SCA / IaC)** | ❌ **BLOQUEO INMEDIATO (`exit 1`)** (Impide el despliegue a AWS) | **7 días (`CRITICAL`)**<br>**15 días (`HIGH`)** | Mitigación obligatoria antes de permitir el paso a ambientes compartidos o producción. |
| **Vulnerabilidad `MEDIUM` o `LOW`** | ⚠️ **ADVERTENCIA (`Warning`)**: Permite continuar el despliegue, archiva el JSON en `reports/` y lo resalta en `reports/security-summary.md` | **30 días (`MEDIUM`)**<br>**90 días (`LOW`)** | No detiene la continuidad operativa, pero deja trazabilidad para remediación planificada en el backlog. |
| **Excepción Arquitectónica Justificada (`exceptions` en `.security-exceptions.yaml`)** | ⚠️ **ADVERTENCIA AUDITADA**: Registrada con ID de regla (`CKV_AWS_116`, `CKV_AWS_117`), justificación técnica, aprobador (`approved_by`) y fecha de vencimiento (`expires_on`). | Revisión antes de `expires_on` | Evita falsos positivos (ej. no meter Lambdas 100% serverless en VPC privada por costos de NAT Gateway) manteniendo trazabilidad para el auditor de la SFC. |

---

## 3. ¿Cómo cumplir con la regulación de la SFC para datos de asegurados (PII)? (100% desde DevOps / IaC)

Para cumplir con la **Ley Estatutaria 1581 de 2012 (Habeas Data)**, la **Circular Externa 007 de 2018 (Ciberseguridad)** y la **Circular Externa 005 de 2019 (Riesgos en Nube)** de la **Superintendencia Financiera de Colombia (SFC)** sin depender de qué programen los desarrolladores backend, implementamos **7 controles nativos en [`infra/template.yaml`](../infra/template.yaml) y en el [`Jenkinsfile`](../Jenkinsfile)**:

| Control Regulatorio SFC | Implementación 100% DevOps / IaC | Dónde está definido |
|---|---|---|
| **1. Enmascaramiento Nativo de PII en CloudWatch Logs (`DataProtectionPolicy`)** | En `ClaimsFunctionLogGroup` configuramos una **`DataProtectionPolicy` nativa de AWS CloudWatch Logs** (`Operation: Deidentify -> MaskConfig: {}`) junto con `LoggingConfig: LogFormat: JSON`. Si una Lambda intenta imprimir un correo o credencial en texto plano, **CloudWatch lo intercepta y lo reemplaza por `*****` antes de guardarlo en disco**, sin depender del código backend. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 66–67 y 207–235) |
| **2. Cifrado en Reposo con Llave Propia del Cliente (`AppKmsKey` — KMS CMK)** | Llave **`AppKmsKey` (`AWS::KMS::Key`)** con **rotación anual automática (`EnableKeyRotation: true`)** y política de acceso restringida que cifra en reposo: (1) Tabla DynamoDB (`ClaimsTable` - `CKV_AWS_119`), (2) Buckets S3 (`ReportsBucket` y `FrontendBucket` - `CKV_AWS_19`), (3) Secretos en Secrets Manager (`IntegrationSecret` - `CKV_AWS_149`), (4) Variables de entorno de las Lambdas (`KmsKeyArn` - `CKV_AWS_173`), (5) LogGroups de CloudWatch (`KmsKeyId` - `CKV_AWS_158`), y (6) Tema de alertas SNS (`KmsMasterKeyId` - `CKV_AWS_26`). | [`infra/template.yaml`](../infra/template.yaml) (Líneas 84–128, 140–180, 240–340 y 470–480) |
| **3. Privacidad Total en S3 (`PublicAccessBlock`) + CloudFront OAC** | Tanto `ReportsBucket` como `FrontendBucket` tienen las **4 banderas de `PublicAccessBlockConfiguration: true`** y políticas de ciclo de vida (`LifecycleConfiguration`). El bucket frontend solo acepta peticiones firmadas con **OAC (`SigV4`)** desde CloudFront, y los reportes PDF solo se entregan mediante **URLs prefirmadas temporales (5 min)**. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 153–170 y 291–336) |
| **4. Cifrado en Tránsito (`TLS 1.2+`) y Perímetro (`WAFv2` + `Cognito`)** | CloudFront fuerza `redirect-to-https` (`TLSv1.2_2021`), activa **AWS WAFv2 (`AWSManagedRulesCommonRuleSet`)** en producción contra ataques OWASP Top 10, y el API Gateway cuenta con autenticación **Amazon Cognito (`AgentsUserPool`)**. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 171–194 y 338–418) |
| **5. Resiliencia, Backups Continuos y Protección contra Borrado** | En `ClaimsTable` está activo **Point-in-Time Recovery (`PITR`)** continuo de 35 días y en producción aplica `DeletionPolicy: Retain` y `UpdateReplacePolicy: Retain`. | [`infra/template.yaml`](../infra/template.yaml) (Líneas 133–147) |
| **6. Retención de Logs por 1 Año y Auditoría de Paso a Producción** | En producción los logs se conservan por **365 días** (`LogRetentionDays: 365`, validado obligatoriamente por `validate-params.sh` en `Stage 2`), y la **Etapa 7 del `Jenkinsfile`** exige aprobación manual registrando `APPROVER_USER`. | [`infra/params/prod.json`](../infra/params/prod.json) y [`Jenkinsfile`](../Jenkinsfile) (Líneas 171–189) |
| **7. Sanitización de PII y Soberanía de Datos al usar IA** | El script `scripts/ai-devops-assistant.sh` filtra cualquier posible cédula o correo con `sanitize_pii` antes de invocar **Amazon Bedrock** dentro de la misma cuenta e infraestructura de AWS (`us-east-1`). | [`scripts/ai-devops-assistant.sh`](../scripts/ai-devops-assistant.sh) (Líneas 21–24) |

---

## 4. Guion Corto para Sustentar el Entregable 4 en la Entrevista (30 segundos)
> *"Para el Entregable 4 integramos en paralelo en la Etapa 4 del `Jenkinsfile`: **Gitleaks** (secretos), **Semgrep** (SAST), **npm audit** (SCA) y **Checkov** (seguridad de IaC), más el triage automático con **Amazon Bedrock**. Manejamos las vulnerabilidades bajo la política de `.security-exceptions.yaml`: secretos y hallazgos Críticos o Altos con fix **bloquean inmediatamente el pipeline**, mientras que Medios y Bajos generan **advertencia con SLA** (30 y 90 días) y quedan resumidos en `security-summary.md`. Para cumplir con la regulación de la **SFC** desde DevOps, implementamos cifrado en reposo con nuestra llave **KMS CMK (`AppKmsKey`)** con rotación anual, una **`DataProtectionPolicy` nativa en CloudWatch Logs** que enmascara datos sensibles con `*****`, buckets S3 100% privados con OAC, **WAFv2**, **Cognito**, **PITR** en DynamoDB y retención de logs de **365 días** en producción."*
