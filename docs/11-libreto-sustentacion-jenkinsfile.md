# Explicación Detallada y Libreto de Sustentación: Pipeline CI/CD (`Jenkinsfile`)

---

## PARTE 1: Explicación Técnica Etapa por Etapa (`Jenkinsfile`)

### 0. Configuración Global (`options`, `parameters`, `environment`)
* **`timestamps()`**: Registra el segundo exacto de cada línea del log (obligatorio para auditoría forense SFC).
* **`disableConcurrentBuilds()`**: Evita que dos despliegues corran al mismo tiempo y bloqueen el estado de CloudFormation.
* **`buildDiscarder(numToKeepStr: '30')`**: Limpia automáticamente builds antiguos para no llenar el disco del servidor Jenkins.
* **`parameters`**: Permite elegir el ambiente objetivo (`TARGET_ENV`) o activar contingencias de reversión (`FORCE_ROLLBACK`).
* **`environment`**: Centraliza la región `us-east-1`, las rutas de credenciales de AWS y el modelo de IA (`amazon.nova-micro-v1:0`).

---

### Etapa 1: Checkout & Metadata (Ruteo Inteligente por Rama - GitFlow)
* Extrae el hash corto del commit (`GIT_COMMIT_SHORT`).
* **Detección dinámica de ambiente según la rama de Git:**
  * Si la rama es `develop` ➔ despliega automáticamente a **`dev`**.
  * Si la rama es `staging` o `release/*` ➔ despliega a **`staging`**.
  * Si la rama es `main` ➔ apunta a **`prod`**.
* **Visibilidad Ejecutiva (`currentBuild.description`):** Escribe en la interfaz de Jenkins el commit, la rama y el ambiente para que cualquier líder o auditor lo vea sin abrir la consola.

---

### Etapa 2: Validate Environment Config & IaC (Shift-Left Quality Gate)
* Ejecuta `bash scripts/validate-params.sh`, auditando con **`check-jsonschema`** que `dev.json`, `staging.json` y `prod.json` cumplan las reglas tipadas de `schema.json` (ej. que `prod` tenga `EnableWaf: true` y `LogRetentionDays: 365`).
* Ejecuta `sam validate` para comprobar que el YAML de CloudFormation no tenga errores de sintaxis.
* **Beneficio:** Si hay un error humano, el pipeline falla en **3 segundos** antes de gastar recursos en AWS.

---

### Etapa 3: Build & Unit Tests (Pruebas Rápidas)
* Entra a `backend/`, instala dependencias con `npm ci`, corre el linter (`npm run lint`) y ejecuta las pruebas unitarias (`npm test`) con el runner nativo de **Node.js 22**.
* Valida la lógica de creación de siniestros, generación de documentos y enmascaramiento de PII (`maskPii`).
* Entra a `frontend/` y empaqueta la Single Page Application (`npm run build`).

---

### Etapa 4: Security Scan (DevSecOps en Paralelo + Triaje con IA)
Ejecuta **4 herramientas de seguridad simultáneamente en paralelo (`parallel`)** ahorrando un 70% de tiempo:
1. **4a. Secret Scanning (`Gitleaks`):** Busca claves de AWS o passwords en el código con `--redact`.
2. **4b. SAST (`Semgrep`):** Analiza vulnerabilidades de código estático contra el **OWASP Top 10**.
3. **4c. SCA (`npm audit`):** Revisa vulnerabilidades críticas en librerías de terceros.
4. **4d. IaC Security (`Checkov`):** Verifica que el template de CloudFormation tenga cifrado KMS, WAF y S3 privado.
* **Post-Stage (Caso de Uso IA #1 - Triage):**  
  Consolida los reportes y ejecuta `ai-devops-assistant.sh triage`, invocando a **Amazon Bedrock (`amazon.nova-micro-v1:0`)** para redactar el dictamen ejecutivo `reports/security-summary.md` y archivarlo en Jenkins.

---

### Etapas 5 y 6: Despliegue a DEV y STAGING + Pruebas de Humo
* **Auto-Remediación (Self-Healing):** Antes de desplegar, verifica si el stack de CloudFormation quedó en estado `ROLLBACK_COMPLETE` por algún intento fallido previo; si es así, lo limpia automáticamente para no bloquear el despliegue.
* **Inyección desde Fuente Única de Verdad:** Extrae los parámetros directamente desde `infra/params/dev.json` (o `staging.json`) con `jq` y los inyecta en `sam deploy --parameter-overrides ${PARAMS}`, usando `samconfig.toml` para las directivas del CLI.
* Ejecuta `deploy-frontend.sh` (S3 sync + invalidación atómica de CloudFront).
* Ejecuta `smoke-test.sh` (4 pruebas en vivo POST/GET/PATCH/PDF contra el API Gateway real).
* Ejecuta `dora-metrics.sh` enviando las métricas de éxito y Lead Time a CloudWatch.

---

### Etapa 7: Manual Approval for PRODUCTION (Compuerta de Auditoría SFC)
* Aplica el principio regulatorio de **Segregación de Funciones y Cuatro Ojos** exigido por la Superintendencia Financiera de Colombia.
* Imprime en pantalla el dictamen de seguridad generado por **Amazon Bedrock**.
* Pausa el pipeline (hasta por 24 horas) esperando que el Oficial de Seguridad o Release Manager haga clic en **"Aprobar y Desplegar a PROD"**.
* Registra el nombre del aprobador en `APPROVER_USER` y lo deja grabado en el historial del build.

---

### Etapa 8: Deploy to PROD (Canary + Auto-Rollback + CloudFront)
* Inyecta los parámetros auditados de `infra/params/prod.json` (`EnableWaf=true`, `LogRetentionDays=365`, `LambdaMemorySize=512`).
* Ejecuta el despliegue con **AWS CodeDeploy (`Canary10Percent5Minutes`)**: desvía solo el 10% del tráfico a la nueva versión durante 5 minutos vigilando las alarmas de CloudWatch. Si hay un error, revierte el tráfico en menos de 60 segundos.
* Actualiza el frontend en CloudFront, corre los smoke tests de producción y publica las métricas DORA productivas.

---

### Bloque `post` (Cierre y Análisis Forense con IA en Fallos)
* **`success`**: Marca la descripción del build como `EXITOSO`.
* **`failure` (Caso de Uso IA #2 - Failure Analysis):**  
  Si cualquier etapa del pipeline falla:
  1. Invoca a **Amazon Bedrock** en modo `failure` para diagnosticar la **causa raíz del fallo** y proponer el comando exacto de solución en `reports/ai-failure-analysis.md`.
  2. Ejecuta `dora-metrics.sh ... FAILURE 4` para registrar el incidente en el **Change Failure Rate (CFR)** y el **MTTR** en CloudWatch.
  3. Archiva todos los reportes para auditoría.

---

# PARTE 2: Guion / Libreto de Exposición para la Entrevista

*(Tiempo de lectura: ~2.5 a 3 minutos. Léelo o expónlo mientras recorres el archivo `Jenkinsfile` de arriba hacia abajo)*

---

## 🎙️ Libreto Continuo: `Jenkinsfile`

> *"Pasando a la orquestación de integración y entrega continua, diseñamos un **`Jenkinsfile` declarativo de 8 etapas** alineado con las normativas de la Superintendencia Financiera de Colombia (SFC):
>
> ---
>
> ### 1. Configuración y Ruteo GitFlow (Etapa 1)
> *"El pipeline inicia fijando controles operativos como **`timestamps`** para trazabilidad forense de cada segundo y **`disableConcurrentBuilds`** para evitar colisiones en CloudFormation.  
> En la **Etapa 1**, implementamos **ruteo automático por ramas (GitFlow)**: si el commit entra por `develop`, apunta automáticamente a **`dev`**; si entra por `staging`, apunta a **`staging`**; y si entra por `main`, apunta a **`prod`**, actualizando dinámicamente la descripción ejecutiva del build en la interfaz de Jenkins.*
>
> ---
>
> ### 2. Shift-Left y Pruebas Rápidas (Etapas 2 y 3)
> *"En la **Etapa 2** aplicamos el principio **Shift-Left**: ejecutamos `validate-params.sh` con `check-jsonschema` y `sam validate`. Si un parámetro incumple el contrato tipado —por ejemplo, si alguien intenta apagar el WAF o bajar la retención de logs en producción—, el pipeline se detiene en 3 segundos sin tocar AWS.  
> Luego, en la **Etapa 3**, compilamos el frontend y ejecutamos el linter y las pruebas unitarias del backend sobre **Node.js 22**, validando la lógica de negocio y el enmascaramiento de datos personales (`maskPii`).*
>
> ---
>
> ### 3. Compuerta DevSecOps en Paralelo + Triaje con IA (Etapa 4)
> *"En la **Etapa 4**, para no penalizar el tiempo de entrega, ejecutamos **cuatro escáneres de seguridad en paralelo**:  
> * **Gitleaks** para detección de secretos con censura activa (`--redact`).  
> * **Semgrep** para análisis estático SAST contra el OWASP Top 10.  
> * **npm audit** para vulnerabilidades en dependencias.  
> * **Checkov** para auditar la seguridad del template de CloudFormation.  
>
> Al finalizar, se activa nuestro **primer caso de uso de Inteligencia Artificial**: el script `ai-devops-assistant.sh` envía los hallazgos a **Amazon Bedrock (modelo Nova Micro)**, el cual genera el dictamen ejecutivo `security-summary.md` archivado en el build.*
>
> ---
>
> ### 4. Despliegues Pre-Productivos con Auto-Remediación (Etapas 5 y 6)
> *"En las **Etapas 5 y 6** desplegamos a `dev` y `staging`. Aquí incorporamos dos prácticas avanzadas:  
> 1. **Self-Healing (Auto-remediación):** El pipeline verifica si el stack previo quedó en estado `ROLLBACK_COMPLETE` y lo limpia automáticamente antes de desplegar.  
> 2. **Fuente Única de Verdad:** Extraemos los parámetros con `jq` directamente desde los archivos `dev.json` y `staging.json` ya validados en la Etapa 2 y los inyectamos en `sam deploy`.  
> Inmediatamente después, sincronizamos el frontend a S3 con invalidación atómica en CloudFront, corremos los **smoke tests en vivo** contra el API Gateway y publicamos las métricas **DORA** en CloudWatch.*
>
> ---
>
> ### 5. Compuerta Regulatoria SFC y Despliegue Canary a Producción (Etapas 7 y 8)
> *"Para cumplir con la **Segregación de Funciones y el Principio de Cuatro Ojos de la SFC**, la **Etapa 7** pausa el pipeline antes de tocar Producción, muestra en consola el dictamen de Amazon Bedrock y exige la aprobación manual de un líder autorizado, registrando su identidad en `APPROVER_USER`.  
> Una vez aprobado, la **Etapa 8** despliega en Producción activando **AWS CodeDeploy con estrategia `Canary10Percent5Minutes`**: envía solo el 10% del tráfico a la nueva versión durante 5 minutos vigilando las alarmas de CloudWatch. Si ocurre un fallo, CodeDeploy ejecuta el **rollback automático en menos de 60 segundos**.*
>
> ---
>
> ### 6. Diagnóstico Forense de Fallos con IA (Bloque `post`)
> *"Finalmente, si cualquier etapa del pipeline falla, el bloque **`post { failure }`** activa nuestro **segundo caso de uso de IA**: consulta a **Amazon Bedrock** en modo SRE para diagnosticar la causa raíz del error y sugerir el comando exacto de remediación, registrando al mismo tiempo el incidente en el indicador *Change Failure Rate* de nuestras métricas DORA en CloudWatch."*

---

## ⚡ Versión Flash / Elevator Pitch (30 segundos)

> *"Nuestro `Jenkinsfile` orquesta 8 etapas automatizadas:  
> 1. Ruteo dinámico por rama GitFlow.  
> 2. Validación Shift-Left de esquemas JSON y plantillas SAM.  
> 3. Pruebas unitarias en Node.js 22.  
> 4. Escaneo DevSecOps paralelo (Gitleaks, Semgrep, npm audit, Checkov) con triaje ejecutivo en **Amazon Bedrock**.  
> 5 y 6. Despliegue a Dev y Staging con auto-remediación de CloudFormation y smoke tests en vivo.  
> 7. Compuerta de aprobación manual auditada bajo norma SFC.  
> 8. Despliegue Canary en Producción con rollback automático en CodeDeploy y registro de métricas DORA en CloudWatch."*
