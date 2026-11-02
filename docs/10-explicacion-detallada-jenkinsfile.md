# Guía Detallada del Pipeline CI/CD (`Jenkinsfile`)

Este documento contiene la explicación técnica minuciosa de cada bloque, directiva y etapa del archivo [`Jenkinsfile`](../Jenkinsfile). Está diseñado bajo el estándar **Declarative Pipeline** de Jenkins, cumpliendo al 100% con los requerimientos del caso práctico y la regulación de la **Superintendencia Financiera de Colombia (SFC)**.

---

## 1. Configuración Base, Opciones y Parámetros (Líneas 1 a 41)

### A) Declaración del Agente y Opciones Operacionales (`options`)
```groovy
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timeout(time: 60, unit: 'MINUTES')
    }
```
- **`agent any`**: Permite la ejecución en cualquier worker/agente de Jenkins disponible que tenga instaladas las herramientas del proyecto (Node 22, Python/Pip, AWS SAM CLI y Git).
- **`timestamps()`**: Estampa la hora exacta (con milisegundos) en cada línea de la consola. **Exigencia de auditoría SFC** para determinar el momento exacto de cada validación, prueba y despliegue.
- **`disableConcurrentBuilds()`**: Impide colisiones. Si dos commits se envían casi al mismo tiempo, Jenkins los encola secuencialmente para evitar bloqueos concurrentes de CloudFormation (`StackLockedException`).
- **`buildDiscarder(logRotator(numToKeepStr: '30'))`**: Política de retención de disco: conserva únicamente los últimos 30 builds, eliminando registros antiguos para evitar la degradación del servidor CI/CD.
- **`timeout(time: 60, unit: 'MINUTES')`**: Mecanismo de corte de seguridad: si un proceso queda bloqueado en bucle, el build se cancela automáticamente tras 60 minutos.

---

### B) Parámetros de Ejecución (`parameters`)
```groovy
    parameters {
        choice(
            name: 'TARGET_ENV',
            choices: ['all (dev -> staging -> prod)', 'dev', 'staging', 'prod'],
            description: 'Ambiente objetivo de despliegue'
        )
        booleanParam(
            name: 'SKIP_PROD_APPROVAL',
            defaultValue: false,
            description: 'Solo para pruebas automatizadas de laboratorio...'
        )
        booleanParam(
            name: 'FORCE_ROLLBACK',
            defaultValue: false,
            description: 'Activar para revertir inmediatamente un ambiente...'
        )
        string(
            name: 'ROLLBACK_COMMIT_SHA',
            defaultValue: '',
            description: 'SHA del artefacto inmutable a restaurar...'
        )
    }
```
- **`TARGET_ENV`**: Permite seleccionar a mano un ambiente si se corre manualmente (*Build with Parameters*).
- **`SKIP_PROD_APPROVAL`**: Bandera booleana (por defecto `false`). En operación real nunca se desactiva; solo se contempla para pruebas sintéticas desatendidas.
- **`FORCE_ROLLBACK` y `ROLLBACK_COMMIT_SHA`**: Nuestro plan de contingencia de nivel de pipeline. Si horas después de un despliegue se detecta una anomalía de negocio, un operador puede forzar la restauración inmediata hacia un commit estable anterior en un clic.

---

### C) Variables de Entorno Globales (`environment`)
```groovy
    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        AWS_REGION         = 'us-east-1'
        PROJECT_NAME       = 'siniestros'
        BEDROCK_MODEL_ID   = 'amazon.nova-micro-v1:0'
        PATH               = "${env.HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${env.PATH}"
    }
```
- Define `us-east-1` como región objetivo (donde residen CloudFront, WAF y Amazon Bedrock).
- Fija el modelo de IA: `amazon.nova-micro-v1:0` (ultra-rápido y con costo inferior a \$0.0001 USD por invocación).
- Asegura que los binarios instalados a nivel de usuario (`checkov`, `sam`, `gitleaks`) sean localizables en el `PATH`.

---

## 2. Las 8 Etapas del Pipeline a Detalle

```
[1. Checkout] ➔ [2. Validate IaC] ➔ [3. Build & Test] ➔ [4. DevSecOps (Paralelo) + AI Triage]
       ➔ [5. Deploy DEV] ➔ [6. Deploy STAGING] ➔ [7. Manual Approval] ➔ [8. Deploy PROD (Canary)]
```

---

### Stage 1: Checkout & Metadata (Líneas 43–66)
```groovy
        stage('1. Checkout & Metadata') {
            steps {
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD 2>/dev/null || echo "localbuild"',
                        returnStdout: true
                    ).trim()

                    def currentBranch = env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""', returnStdout: true).trim()
                    if (currentBranch == 'develop') {
                        env.EFFECTIVE_ENV = 'dev'
                    } else if (currentBranch == 'staging' || currentBranch.startsWith('release/')) {
                        env.EFFECTIVE_ENV = 'staging'
                    } else if (currentBranch == 'main' || currentBranch == 'master') {
                        env.EFFECTIVE_ENV = (params.TARGET_ENV == 'dev' || params.TARGET_ENV == 'staging') ? params.TARGET_ENV : 'prod'
                    } else {
                        env.EFFECTIVE_ENV = params.TARGET_ENV
                    }
                    ...
                }
                sh 'mkdir -p reports'
            }
        }
```
- **Detección Dinámica de Ambientes (GitFlow):**
  - Si el push/PR proviene de `develop` $\rightarrow$ fija `EFFECTIVE_ENV = 'dev'`.
  - Si proviene de `staging` o `release/*` $\rightarrow$ fija `EFFECTIVE_ENV = 'staging'`.
  - Si proviene de `main` $\rightarrow$ fija `EFFECTIVE_ENV = 'prod'`.
- **Plus CI/CD (`currentBuild.description`):** Inyecta en la cabecera del build de Jenkins los metadatos dinámicos: `Commit: <sha> | Rama: <branch> | Env: <env> | Estado: <estado>`, dándole visibilidad ejecutiva a auditores y gerentes técnicos directamente en la web de Jenkins.
- Crea el directorio `reports/` donde se consolidarán los artefactos de seguridad y pruebas.

---

### Stage 2: Validate Environment Config & IaC (Líneas 68–78)
```groovy
        stage('2. Validate Environment Config & IaC') {
            steps {
                echo '[IaC Gate] Validando consistencia de parametros (dev, staging, prod) contra JSON Schema...'
                sh 'bash scripts/validate-params.sh'

                echo '[IaC Gate] Ejecutando sam validate sobre infra/template.yaml...'
                sh 'sam validate -t infra/template.yaml --region ${AWS_REGION}'
            }
        }
```
- **Resuelve el Problema #5 (Configuración Inconsistente):**
  1. `validate-params.sh` valida que `dev.json`, `staging.json` y `prod.json` cumplan estrictamente el esquema `schema.json` con `check-jsonschema`. Comprueba rangos de memoria (128–3008 MB), runtimes permitidos y que `prod` tenga `LogRetentionDays >= 365` y `EnableWaf: true`.
  2. `sam validate` valida la sintaxis CloudFormation/SAM y referencias intrínsecas antes de compilar código.
- **Fail-Fast:** Si un parámetro fue editado erróneamente, el pipeline aborta en 3 segundos sin interactuar con AWS.

---

### Stage 3: Build & Unit Tests (Líneas 80–94)
```groovy
        stage('3. Build & Unit Tests') {
            steps {
                dir('backend') {
                    sh '''
                        npm run lint
                        npm test
                    '''
                }
                dir('frontend') {
                    sh 'npm run build'
                }
            }
        }
```
- **Backend:**
  - `npm run lint` (`node --check`): Valida la sintaxis de los módulos ESM de las Lambdas (`claims/index.mjs` y `documents/index.mjs`).
  - `npm test`: Ejecuta las pruebas unitarias nativas con el runner de Node 22 (`backend/tests/backend.test.mjs`). Verifica el registro de siniestros, generación de URLs y el enmascaramiento de PII (`maskPii`). Ejecución ultrarrápida en ~10 ms.
- **Frontend:**
  - `npm run build`: Empaqueta la SPA en `frontend/dist/index.html`.

---

### Stage 4: DevSecOps Gate + AI Triage (Líneas 96–145)
**Resuelve el Problema #3 (Sin análisis de seguridad):** Ejecuta **4 escáneres en paralelo** (`parallel`) reduciendo el tiempo de escaneo total en un 70%:

```groovy
        stage('4. Security Scan (DevSecOps Gate + AI Triage)') {
            parallel {
                stage('4a. Secret Scanning (Gitleaks)') {
                    steps {
                        sh '''
                            gitleaks detect --source backend --no-git --redact --report-format json --report-path reports/gitleaks-backend.json
                            gitleaks detect --source frontend --no-git --redact --report-format json --report-path reports/gitleaks-frontend.json
                            gitleaks detect --source infra --no-git --redact --report-format json --report-path reports/gitleaks-infra.json
                        '''
                    }
                }
                stage('4b. SAST (Semgrep OWASP)') {
                    steps {
                        sh 'semgrep scan --config p/default backend/claims backend/documents --json --output reports/semgrep-sast.json || true'
                    }
                }
                stage('4c. SCA Dependency Audit (npm audit)') {
                    steps {
                        dir('backend') {
                            sh 'npm audit --audit-level=high --json > ../reports/npm-audit-backend.json || true'
                        }
                    }
                }
                stage('4d. IaC Security Scan (Checkov)') {
                    steps {
                        sh 'checkov -f infra/template.yaml --framework cloudformation --soft-fail -o json > reports/checkov-iac.json'
                    }
                }
            }
```

| Escáner | Alcance | Qué busca | Política en [`.security-exceptions.yaml`](../.security-exceptions.yaml) |
|---|---|---|---|
| **Gitleaks** | `backend/`, `frontend/`, `infra/` | Claves AWS (`AKIA...`), contraseñas, tokens JWT, private keys. | Hallazgo = **Bloqueo Inmediato (`exit 1`)**. |
| **Semgrep** | Handlers de Lambdas | Inyecciones, sanitización de entradas, OWASP Top 10. | `CRITICAL`/`HIGH` = **Bloqueo**. `MEDIUM`/`LOW` = **Alerta (SLA 30/90d)**. |
| **npm audit** | Árbol de dependencias | CVEs públicos en paquetes de Node. | Vulnerabilidades `HIGH`/`CRITICAL` con parche = **Bloqueo**. |
| **Checkov** | `infra/template.yaml` | Cifrado KMS, bloqueo público S3, PITR DynamoDB, IAM mínimo. | Viola reglas base sin excepción auditada = **Bloqueo**. |

#### Post-Stage 4: Triage Inteligente con Amazon Bedrock (Caso de Uso #1 de IA)
```groovy
            post {
                success {
                    sh '''
                        cat reports/npm-audit-backend.json reports/gitleaks-backend.json > reports/combined-security.txt || true
                        bash scripts/ai-devops-assistant.sh triage reports/combined-security.txt reports/security-summary.md
                        cat reports/security-summary.md
                    '''
                    archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
                }
            }
```
- Consolida los hallazgos en un informe sanitizado sin PII (`sanitize_pii`).
- Invoca **Amazon Bedrock (`amazon.nova-micro-v1:0`)**, el cual redacta un dictamen ejecutivo en `reports/security-summary.md` contextualizado bajo la normativa **SFC (CE 007/2018)**.
- `archiveArtifacts` almacena los reportes como evidencia inmutable para auditorías.

---

### Stage 5: Deploy to DEV & Smoke Tests (Líneas 147–164)
```groovy
        stage('5. Deploy to DEV & Smoke Tests') {
            when {
                expression { return env.EFFECTIVE_ENV == 'all (dev -> staging -> prod)' || env.EFFECTIVE_ENV == 'dev' }
            }
            steps {
                sh '''
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file infra/samconfig.toml \
                      --config-env dev \
                      --region "${AWS_REGION}"

                    bash scripts/deploy-frontend.sh dev
                    bash scripts/smoke-test.sh dev
                    bash scripts/dora-metrics.sh dev SUCCESS 0
                '''
            }
        }
```
- Despliega el stack `siniestros-dev` en CloudFormation con estrategia `AllAtOnce`.
- `deploy-frontend.sh dev`: Sincroniza el frontend al bucket S3 privado e invalida CloudFront.
- `smoke-test.sh dev`: Ejecuta pruebas funcionales con `curl` sobre los endpoints (`GET /health`, `POST /claims`) validando respuestas 200/201.
- `dora-metrics.sh dev SUCCESS 0`: Registra `DeploymentFrequency = 1` y `ChangeFailureCount = 0` en CloudWatch (`SiniestrosDORA`).

---

### Stage 6: Deploy to STAGING & Integration Tests (Líneas 166–183)
- Misma automatización que en `dev`, pero apuntando a `--config-env staging`.
- En este ambiente, las Lambdas aplican despliegue progresivo **`Linear10PercentEvery1Minute`** para pruebas de integración QA.

---

### Stage 7: Manual Approval for PRODUCTION (SFC Audit Gate) (Líneas 185–204)
```groovy
        stage('7. Manual Approval for PRODUCTION (SFC Audit Gate)') {
            when {
                expression { return (env.EFFECTIVE_ENV == 'all (dev -> staging -> prod)' || env.EFFECTIVE_ENV == 'prod') && !params.SKIP_PROD_APPROVAL }
            }
            steps {
                script {
                    def summary = fileExists('reports/security-summary.md') ? readFile('reports/security-summary.md') : 'All scans passed.'
                    echo "=== RESUMEN DE SEGURIDAD & IA PARA EL APROBADOR ===\n${summary}"
                    timeout(time: 24, unit: 'HOURS') {
                        input(
                            message: "¿Aprobar despliegue Canary a PRODUCCIÓN (Commit ${env.GIT_COMMIT_SHORT}) bajo cumplimiento SFC?",
                            ok: 'Aprobar y Desplegar a PROD',
                            submitterParameter: 'APPROVER_USER'
                        )
                    }
                    echo "[SFC Audit] Despliegue a PROD aprobado por: ${env.APPROVER_USER ?: 'ReleaseManager'}"
                }
            }
        }
```
- **Cumplimiento Regulatorio SFC:**
  1. Muestra en pantalla el dictamen de seguridad generado por Bedrock para que la aprobación sea informada y no a ciegas.
  2. Pausa la ejecución (`input`) requiriendo la intervención de un líder técnico o de seguridad.
  3. **`submitterParameter: 'APPROVER_USER'`**: Captura el usuario autenticado que autorizó el paso a producción y lo deja registrado en el log inmutable del build.
  4. Si transcurren 24 horas sin autorización, el pipeline aborta automáticamente sin tocar producción.

---

### Stage 8: Deploy to PROD (Canary + Auto-Rollback) (Líneas 206–223)
```groovy
        stage('8. Deploy to PROD (Canary + Auto-Rollback + CloudFront Invalidation)') {
            when {
                expression { return env.EFFECTIVE_ENV == 'all (dev -> staging -> prod)' || env.EFFECTIVE_ENV == 'prod' }
            }
            steps {
                sh '''
                    sam deploy \
                      --template-file infra/template.yaml \
                      --config-file infra/samconfig.toml \
                      --config-env prod \
                      --region "${AWS_REGION}"

                    bash scripts/deploy-frontend.sh prod
                    bash scripts/smoke-test.sh prod
                    bash scripts/dora-metrics.sh prod SUCCESS 0
                '''
            }
        }
```
- Despliega el stack `siniestros-prod`.
- **Estrategia Canary en AWS CodeDeploy:** Activa **`Canary10Percent5Minutes`**. Durante 5 minutos, CodeDeploy vigila las alarmas `ClaimsFunctionErrorsAlarm`, `DocumentsFunctionErrorsAlarm` y `ApiGateway5xxAlarm`. Ante cualquier error, revierte el alias `:live` de inmediato.
- Actualiza el portal SPA e invalida CloudFront en producción.

---

## 3. Bloque `post`: Diagnóstico con IA y Métricas DORA (Líneas 225–239)

```groovy
    post {
        failure {
            echo '[AI Case #1] Analizando causa raiz del fallo con Amazon Bedrock y registrando CFR en DORA...'
            sh '''
                bash scripts/ai-devops-assistant.sh failure reports/combined-security.txt reports/ai-failure-analysis.md || true
                cat reports/ai-failure-analysis.md || true
                bash scripts/dora-metrics.sh "${TARGET_ENV}" FAILURE 4 || true
            '''
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
        }
        always {
            echo "[CI/CD] Ejecucion finalizada para commit ${env.GIT_COMMIT_SHORT}."
        }
    }
```
- **Caso de Uso #2 de IA (RCA Automático):** Si cualquier paso falla:
  1. Captura las últimas líneas del log, aplica `sanitize_pii` para no filtrar datos sensibles y llama a **Amazon Bedrock**.
  2. Bedrock analiza el contexto y genera `reports/ai-failure-analysis.md` indicando la **causa raíz exacta** y el **comando o cambio en código para corregirlo**, reduciendo el MTTR.
  3. Ejecuta `dora-metrics.sh` con `FAILURE`, publicando `ChangeFailureCount = 1` y registrando el impacto en CloudWatch.
  4. Archiva todos los reportes para su descarga directa.

