# Entregables 1 y 3: Pipeline CI/CD en Jenkins y Estrategia de Despliegue

---

## Entregable 1: Pipeline CI/CD (`Jenkinsfile`)

> **Requisito del PDF:**
> - *Diseñar un pipeline completo (Jenkins o GitHub Actions) que cubra: `Checkout → Build → Test → Security Scan → Deploy`*
> - *Despliegue diferenciado por ambiente*
> - *Aprobación manual para producción*

---

### 1.1 Cobertura del Flujo `Checkout → Build → Test → Security Scan → Deploy`

El archivo [`Jenkinsfile`](../Jenkinsfile) implementa un **Pipeline Declarativo de 8 etapas** (más un bloque `post { failure }` de diagnóstico con IA) donde cada fase solicitada en el PDF está mapeada de forma explícita:

| Fase Pedida en el PDF | Etapa(s) en [`Jenkinsfile`](../Jenkinsfile) | Líneas | Comandos Exactos que Ejecuta | Qué valida / Qué artefacto produce |
|---|---|---|---|---|
| **1. Checkout** | **`Stage 1: Checkout & Metadata`** | L30–43 | `git rev-parse --short HEAD`<br>`rm -rf reports && mkdir -p reports` | Clona el código, identifica el commit (`GIT_COMMIT_SHORT`), asigna el ambiente destino (`TARGET_ENV`) y limpia el directorio de reportes para evitar artefactos residuales de builds previos. |
| **2. Pre-Validate (IaC & Params)** | **`Stage 2: Validate Environment Config & IaC`** | L45–55 | `bash scripts/validate-params.sh`<br>`sam validate -t infra/template.yaml` | Valida `dev.json`, `staging.json` y `prod.json` contra [`schema.json`](../infra/params/schema.json) y valida la sintaxis de CloudFormation/SAM antes de compilar. |
| **3. Build & Test** | **`Stage 3: Build & Unit Tests`** | L57–73 | **Backend:** `npm run lint` (`node --check`) + `npm test` (`node --test`)<br>**Frontend:** `npm run build` | Verifica sintaxis ESM de las 2 Lambdas, ejecuta las pruebas unitarias en [`backend/tests/backend.test.mjs`](../backend/tests/backend.test.mjs) y empaqueta el SPA en `frontend/dist/index.html`. |
| **4. Security Scan** | **`Stage 4: Security Scan (DevSecOps Gate + AI Triage)`** | L75–125 | En **4 hilos paralelos**:<br>• `4a`: `gitleaks detect` (Secretos, `--redact`)<br>• `4b`: `semgrep scan` (SAST, OWASP Top 10)<br>• `4c`: `npm audit --audit-level=high` (SCA)<br>• `4d`: `checkov -f infra/template.yaml --hard-fail-on <16 checks>` (IaC)<br>• **Post-Stage (`always`):** `ai-devops-assistant.sh triage` + `archiveArtifacts` | Evalúa las 4 capas de seguridad. Si se incumple algún Quality Gate crítico, bloquea el despliegue. Bedrock (`amazon.nova-micro-v1:0`) sintetiza los hallazgos en `reports/security-summary.md` y archiva las evidencias. |
| **5. Deploy (`dev` / `staging`)** | **`Stage 5: Deploy to DEV`**<br>**`Stage 6: Deploy to STAGING`** | L127–178 | Auto-remediación `ROLLBACK_COMPLETE`<br>`sam deploy --config-file infra/samconfig.toml --config-env dev|staging`<br>`bash scripts/deploy-frontend.sh <env>`<br>`bash scripts/smoke-test.sh <env>`<br>`bash scripts/dora-metrics.sh <env>` | Limpia stacks zombies si existen, despliega el stack en AWS mediante SAM, sincroniza el frontend en S3, invalida CloudFront, prueba los endpoints con `curl` y publica métricas DORA. |
| **6. Manual Approval** | **`Stage 7: Manual Approval for PRODUCTION`** | L180–199 | `readFile('reports/security-summary.md')`<br>`input(message: ..., submitterParameter: 'APPROVER_USER')` | Muestra el dictamen de seguridad de Bedrock, pausa la ejecución y registra el usuario que autorizó el paso a `prod` para auditoría SFC (inviolable, sin bypass). |
| **7. Deploy (`prod`)** | **`Stage 8: Deploy to PROD`** | L201–227 | Auto-remediación `ROLLBACK_COMPLETE`<br>`sam deploy --config-file infra/samconfig.toml --config-env prod`<br>`bash scripts/deploy-frontend.sh prod`<br>`bash scripts/smoke-test.sh prod`<br>`bash scripts/dora-metrics.sh prod` | Despliega en producción con estrategia **`Canary10Percent5Minutes`**, activa WAFv2, invalida CloudFront y verifica salud con smoke tests. |
| **8. Post-Failure (RCA con IA)** | **`post { failure }`** | L237–250 | `bash scripts/ai-devops-assistant.sh failure`<br>`bash scripts/dora-metrics.sh <env> FAILURE` | Si cualquier etapa falla, **Amazon Bedrock** analiza la causa raíz, genera `reports/ai-failure-analysis.md` y registra el fallo en las métricas DORA. |

---

### 1.2 Despliegue Diferenciado por Ambiente (`dev`, `staging`, `prod`)

Usamos **una sola plantilla de infraestructura ([`infra/template.yaml`](../infra/template.yaml))** y diferenciamos el comportamiento de cada ambiente mediante [`infra/samconfig.toml`](../infra/samconfig.toml) (`--config-env dev | staging | prod`) y [`infra/params/{dev,staging,prod}.json`](../infra/params/):

| Característica / Parámetro | Ambiente `dev` (`Stage 5`) | Ambiente `staging` (`Stage 6`) | Ambiente `prod` (`Stage 8`) | ¿Cómo se controla en IaC / Pipeline? |
|---|---|---|---|---|
| **Nombre del Stack en AWS** | `siniestros-dev` | `siniestros-staging` | `siniestros-prod` | `stack_name` en [`infra/samconfig.toml`](../infra/samconfig.toml) |
| **Estrategia de Despliegue Lambda (CodeDeploy)** | `AllAtOnce` (Inmediato para agilidad en pruebas) | `Linear10PercentEvery1Minute` (10% cada minuto por 10 min) | **`Canary10Percent5Minutes`** (10% por 5 min + Auto-Rollback) | Parámetro `DeploymentPreferenceType` en `template.yaml` |
| **Memoria / Timeout de Lambdas** | `256 MB` / `10 seg` | `512 MB` / `15 seg` | `1024 MB` / `20 seg` | Parámetros `LambdaMemorySize` y `LambdaTimeout` |
| **Protección Perimetral AWS WAFv2** | `false` (Ahorro de costos en desarrollo) | `false` (Ahorro de costos en QA) | **`true` (`AWSManagedRulesCommonRuleSet`)** | Condición `ShouldDeployWaf` (`EnableWaf = true` en `prod`) |
| **Retención de Logs en CloudWatch** | `7 días` | `30 días` | **`365 días` (1 año — Exigencia SFC)** | Parámetro `LogRetentionDays` validado en `Stage 2` |
| **Protección contra Borrado en DynamoDB** | `Delete` (Permite limpiar rápido el laboratorio) | `Delete` | **`Retain` (`DeletionPolicy` y `UpdateReplacePolicy`)** | Condición `IsProd` en `ClaimsTable` (`template.yaml`) |
| **Compuerta de Aprobación Humana** | Automático | Automático tras pasar `dev` | **Requiere `Stage 7: Manual Approval` (`APPROVER_USER`)** | Condición `when` en `Stage 7` del `Jenkinsfile` |

---

### 1.3 Aprobación Manual para Producción (`Stage 7` — Cumplimiento SFC)

En las líneas **171–189** del [`Jenkinsfile`](../Jenkinsfile), antes de ejecutar `Stage 8 (Deploy to PROD)`, el pipeline ejecuta una compuerta formal de gobierno:

```groovy
stage('7. Manual Approval for PRODUCTION (SFC Audit Gate)') {
    when {
        expression { return params.TARGET_ENV == 'all (dev -> staging -> prod)' || params.TARGET_ENV == 'prod' }
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
            currentBuild.description = "${currentBuild.description} | Aprobador: ${env.APPROVER_USER ?: 'ReleaseManager'}"
        }
    }
}
```
- **¿Por qué está diseñado así?**
  1. **Decisión Informada con IA:** Antes de mostrar el botón de aprobación, imprime en consola el dictamen `reports/security-summary.md` generado por **Amazon Bedrock** en la Etapa 4.
  2. **Auditoría SFC (`submitterParameter: 'APPROVER_USER'`):** Captura el ID del usuario que hizo clic en *"Aprobar"* y lo deja registrado en el log inmutable del build.
  3. **Seguridad por Timeout (`timeout(time: 24, unit: 'HOURS')`):** Si nadie aprueba el cambio dentro de la ventana establecida, el pipeline se cancela automáticamente sin desplegar en producción.

---

### 1.4 Guion Corto para Sustentar el Entregable 1 en la Entrevista (30 segundos)
> *"Para el Entregable 1 diseñamos un `Jenkinsfile` declarativo de 8 etapas que cubre de punta a punta `Checkout → Validate IaC → Build & Unit Test → Security Scan Paralelo → Deploy`. El despliegue es diferenciado por ambiente usando un único `infra/template.yaml` junto con `infra/samconfig.toml` y `infra/params/*.json`: `dev` despliega `AllAtOnce` con 256 MB y retención de 7 días; `staging` usa despliegue `Linear10PercentEvery1Minute`; y `prod` pasa primero por la Etapa 7 de **Aprobación Manual**, que muestra el dictamen de seguridad generado por **Amazon Bedrock**, registra quién aprobó el cambio (`APPROVER_USER`) para auditoría de la SFC y despliega con `Canary10Percent5Minutes`, WAFv2 activo y retención de logs de 365 días."*

---

## Entregable 3: Estrategia de Despliegue y Rollback Automático

> **Requisitos del PDF:**
> - *Proponer estrategia (blue/green, canary, rolling) para las Lambdas*
> - *Definir mecanismo de rollback automático*
> - *¿Cómo desplegar el frontend (S3 + CloudFront invalidation)?*

---

### 3.1 Estrategia Propuesta para las Funciones Lambda (Canary + Linear + AllAtOnce)

#### ¿Por qué elegimos **Canary (`Canary10Percent5Minutes`)** en Producción frente a Blue/Green o Rolling?

| Estrategia Evaluada | Cómo funciona en AWS Lambda / CodeDeploy | Ventajas y Desventajas | ¿Dónde la usamos en nuestro proyecto? |
|---|---|---|---|
| **AllAtOnce (Blue/Green instantáneo)** | Cambia el **100% del tráfico** del alias `:live` a la nueva versión de inmediato. | Muy rápido (segundos), pero si hay un bug afecta al 100% de los agentes al instante. | **`dev` (`AllAtOnce`)**: Ideal para iterar rápido en desarrollo. |
| **Linear (Rolling progresivo)** | Transfiere el tráfico en incrementos iguales cada minuto (`Linear10PercentEvery1Minute` = 10% más por minuto durante 10 min). | Transición suave y predecible para pruebas de carga e integración. | **`staging` (`Linear10PercentEvery1Minute`)**: Ideal para pruebas de integración QA. |
| **Canary (`Canary10Percent5Minutes`)** | Envía solo el **10% del tráfico real** a la nueva versión (`v2`) durante **5 minutos** mientras el **90% sigue en la versión estable (`v1`)**. Pasados los 5 min sin alarmas, pasa el 100% a `v2`. | **Limita el radio de impacto (*Blast Radius*) al 10%** en producción y permite detectar errores reales antes de exponer a todos los agentes de seguros. | **🎯 `prod` (`Canary10Percent5Minutes`)**: Nuestra estrategia principal de producción. |

#### Implementación Exacta en [`infra/template.yaml`](../infra/template.yaml) (Líneas 230–235 y 277–282):
```yaml
      AutoPublishAlias: live
      DeploymentPreference:
        Type: !Ref DeploymentPreferenceType
        Alarms:
          - !Ref ClaimsFunctionErrorsAlarm
          - !Ref ApiGateway5xxAlarm
```
- Cuando se ejecuta `sam deploy`, CloudFormation transforma este bloque en un `AWS::CodeDeploy::Application` y un `AWS::CodeDeploy::DeploymentGroup` que administra automáticamente los pesos de tráfico entre la versión anterior (`v1`) y la nueva versión (`v2`) sobre el alias `:live`.

---

### 3.2 Mecanismo de Rollback Automático (De > 1 hora manual a < 1 minuto automático)

Implementamos **3 niveles de Rollback** para cubrir funciones Lambda, infraestructura CloudFormation y frontend:

| Nivel de Rollback | Qué lo dispara automáticamente | Cómo actúa técnicamente | Tiempo de Recuperación (MTTR) |
|---|---|---|---|
| **1. Rollback Automático de Tráfico Lambda (AWS CodeDeploy + CloudWatch Alarms)** | Si durante la ventana Canary (5 min) se activa cualquiera de las 3 alarmas en CloudWatch:<br>• `ClaimsFunctionErrorsAlarm` (`Errors >= 1` en 1 min)<br>• `DocumentsFunctionErrorsAlarm` (`Errors >= 1` en 1 min)<br>• `ApiGateway5xxAlarm` (`5XXError >= 2` en 1 min) | **AWS CodeDeploy aborta inmediatamente el despliegue** y devuelve el **100% del peso del alias `:live`** a la versión inmutable anterior (`v1`), publicando además una alerta en el tópico SNS `AlertsTopic`. | **< 1 minuto (100% automático, sin intervención humana)** |
| **2. Rollback Automático de Infraestructura (AWS CloudFormation + Auto-Remediación)** | Si cualquier recurso de `infra/template.yaml` falla al crearse o actualizarse durante `sam deploy`. | CloudFormation detiene la actualización y ejecuta `UPDATE_ROLLBACK_IN_PROGRESS` regresando al estado previo estable. Además, si el stack queda en el estado zombie `ROLLBACK_COMPLETE`, el pipeline lo detecta automáticamente, lo elimina con `delete-stack` y espera `stack-delete-complete` para recreación limpia. | **1 a 2 minutos (100% automático)** |
| **3. Rollback Controlado por Git / Trazabilidad de Auditoría** | Si un error funcional de negocio se detecta horas después del despliegue en producción. | Siguiendo las directivas de auditoría de la SFC, el rollback se gestiona mediante Git (*GitOps*): se re-ejecuta el build sobre el commit o tag anterior estable (`git revert` o checkout de versión previa), manteniendo la pista de auditoría inalterable sin recurrir a parámetros que alteren la lógica del pipeline. | **2 a 3 minutos (Desencadenado en Jenkins)** |

---

### 3.3 ¿Cómo desplegar el Frontend (S3 + CloudFront Invalidation)?

El despliegue del portal web SPA está 100% automatizado en el script [`scripts/deploy-frontend.sh`](../scripts/deploy-frontend.sh) (invocado en las **Etapas 5, 6 y 8** del [`Jenkinsfile`](../Jenkinsfile)):

| Paso en `deploy-frontend.sh` | Comando AWS CLI Ejecutado | Por qué se hace así (Buenas Prácticas DevOps / CloudFront) |
|---|---|---|
| **Paso 1: Descubrimiento Dinámico de Recursos** | `aws cloudformation describe-stacks --stack-name siniestros-${ENV}` | Obtiene dinámicamente `FrontendBucketName` y `CloudFrontDistributionId` desde los `Outputs` del stack sin hardcodear nombres de buckets ni IDs de distribución. |
| **Paso 2: Subida de Assets Estáticos con Caché Larga (1 año)** | `aws s3 sync frontend/dist/ s3://${FRONTEND_BUCKET}/ --exclude "index.html" --cache-control "public, max-age=31536000, immutable" --delete` | Los archivos `.js`, `.css` e imágenes con hash se cachean por **1 año** en los Edge Locations de CloudFront para máxima velocidad y mínimo costo de transferencia. El flag `--delete` limpia archivos obsoletos. |
| **Paso 3: Subida Atómica de `index.html` con `no-cache`** | `aws s3 cp frontend/dist/index.html s3://${FRONTEND_BUCKET}/index.html --cache-control "no-cache, no-store, must-revalidate"` | Se sube **al final** (después de que todos los assets ya existen en S3) y con cabecera `no-cache` para que el navegador de los agentes siempre pida la última referencia del portal. |
| **Paso 4: Invalidación Selectiva de Caché en CloudFront** | `aws cloudfront create-invalidation --distribution-id "${CF_DIST_ID}" --paths "/index.html" "/"` | Purga únicamente `/index.html` y `/` en todos los nodos de borde de CloudFront en segundos, manteniéndose siempre dentro de la capa gratuita de AWS (**1,000 rutas gratis/mes** en lugar de desperdiciar cuota con `/*`). |

---

### 3.4 Guion Corto para Sustentar el Entregable 3 en la Entrevista (30 segundos)
> *"Para el Entregable 3 implementamos en `infra/template.yaml` el versionado inmutable de las Lambdas con `AutoPublishAlias: live` y **AWS CodeDeploy** diferenciando por ambiente: `AllAtOnce` en `dev`, `Linear10PercentEvery1Minute` en `staging` y **`Canary10Percent5Minutes`** en `prod`. El rollback es 100% automático y toma menos de 1 minuto: CodeDeploy vigila las alarmas `ClaimsFunctionErrorsAlarm`, `DocumentsFunctionErrorsAlarm` y `ApiGateway5xxAlarm` en CloudWatch, y si ocurre un solo error en ese 10% de tráfico Canary, regresa automáticamente el alias `live` a la versión anterior estable. Para el frontend, el script `scripts/deploy-frontend.sh` sincroniza los assets a S3 privado con caché de 1 año, sube `index.html` con `no-cache` y ejecuta `aws cloudfront create-invalidation` sobre `/index.html` y `/`."*
