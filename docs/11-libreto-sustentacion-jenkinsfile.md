# Libreto de Exposición: Pipeline CI/CD (`Jenkinsfile`)

> **Tiempo estimado:** ~3 minutos. Léelo mientras recorres el `Jenkinsfile` de arriba hacia abajo.

---

## 🎙️ Libreto Continuo

"Toda la entrega continua está orquestada en un **`Jenkinsfile` declarativo de 8 etapas**, alineado con los controles de la Superintendencia Financiera (SFC).

### Cabecera (options, parameters, environment)
Fijamos **`timestamps`** para trazabilidad de auditoría, **`disableConcurrentBuilds`** para evitar que dos ejecuciones colisionen sobre el mismo stack de CloudFormation, y **`buildDiscarder`** para conservar solo los últimos 30 builds. El parámetro **`TARGET_ENV`** permite elegir el ambiente a desplegar: `dev`, `staging`, `prod` o toda la cadena. En `environment` definimos la región `us-east-1`, la ruta de las credenciales de AWS dentro del contenedor, el modelo de Bedrock y el `PATH` con las herramientas (SAM, Checkov, Semgrep).

### Etapa 1: Checkout & Metadata
Captura el hash corto del commit y registra el ambiente seleccionado en la descripción del build, dejando trazabilidad visible en Jenkins. Crea la carpeta `reports/` donde se guardarán las evidencias.

### Etapa 2: Validación Shift-Left
Ejecuta `validate-params.sh`, que valida `dev.json`, `staging.json` y `prod.json` contra `schema.json` con **`check-jsonschema`**, y `sam validate` sobre el template. Si hay un parámetro inválido, el pipeline falla en segundos **sin tocar AWS**.

### Etapa 3: Build y Pruebas Unitarias
Instala dependencias, corre el linter y las pruebas unitarias del backend sobre **Node.js 22** (lógica de siniestros, documentos y enmascaramiento de PII), y empaqueta el frontend.

### Etapa 4: Compuerta DevSecOps en Paralelo + Triaje con IA
Ejecuta **cuatro escáneres simultáneos**: **Gitleaks** (secretos, con `--redact`), **Semgrep** (SAST, OWASP), **npm audit** (dependencias) y **Checkov** (seguridad de la IaC). Al terminar, `ai-devops-assistant.sh` envía los hallazgos a **Amazon Bedrock (Nova Micro)**, que genera el dictamen ejecutivo `security-summary.md`, archivado como evidencia.

### Etapas 5 y 6: Despliegue a DEV y STAGING
Antes de desplegar, el pipeline hace **auto-remediación**: si el stack quedó en `ROLLBACK_COMPLETE` por un intento previo, lo elimina. Luego lee los parámetros del ambiente desde `infra/params/<env>.json` con `jq` —los mismos ya validados en la Etapa 2— y los inyecta en **`sam deploy`**, mientras `samconfig.toml` aporta solo las directivas del CLI. Después sube el frontend a S3 con invalidación en CloudFront, ejecuta **smoke tests reales** contra el API y publica las **métricas DORA** en CloudWatch.

### Etapa 7: Aprobación Manual para Producción
Por **Segregación de Funciones y Principio de Cuatro Ojos**, el pipeline se detiene, muestra el dictamen de Bedrock y exige que un aprobador autorizado confirme. Su identidad queda registrada en `APPROVER_USER`. No existe ningún parámetro para saltarse este control, y si pasan 24 horas sin respuesta, el pipeline se cancela.

### Etapa 8: Despliegue a PRODUCCIÓN
Despliega con parámetros de `prod.json` (WAF activo, 365 días de retención) usando **CodeDeploy con `Canary10Percent5Minutes`**: 10% del tráfico durante 5 minutos vigilado por alarmas de CloudWatch. Si una alarma se dispara, CodeDeploy hace **rollback automático** a la versión previa. Luego actualiza el frontend, corre el smoke test final y registra métricas DORA.

### Bloque post
Si cualquier etapa falla, se activa el segundo uso de IA: Bedrock analiza el error y propone la causa raíz y el comando de remediación en `ai-failure-analysis.md`, y el fallo se registra en las métricas DORA (Change Failure Rate)."

---

## ⚡ Versión Flash (30 segundos)

> "El `Jenkinsfile` tiene 8 etapas: metadata del build; validación Shift-Left de parámetros y template; pruebas unitarias; escaneo DevSecOps en paralelo con triaje de IA en Bedrock; despliegue a dev y staging con smoke tests y métricas DORA; aprobación manual obligatoria bajo norma SFC; y despliegue a producción con Canary y rollback automático. Si algo falla, la IA diagnostica la causa raíz."

---

## 🛡️ Preguntas Probables del Jurado

**1. ¿Cómo se elige el ambiente?**  
Con el parámetro `TARGET_ENV` al ejecutar el build. Cada stage de despliegue tiene un `when` que solo corre si coincide con la selección.

**2. ¿Puede alguien saltarse la aprobación de producción?**  
No. La Etapa 7 es obligatoria siempre que el despliegue incluya `prod`.

**3. ¿Cómo hacen rollback?**  
Automático en producción con CodeDeploy Canary y alarmas de CloudWatch. Para un rollback manual se vuelve a ejecutar el pipeline sobre un commit anterior.

**4. ¿Por qué los parámetros salen de los `.json` y no del `samconfig.toml`?**  
Para tener una única fuente de verdad: lo que se valida en la Etapa 2 es exactamente lo que se despliega.
