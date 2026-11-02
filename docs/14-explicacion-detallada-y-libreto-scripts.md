# Explicación Detallada y Libreto de Sustentación: Scripts de Automatización (`scripts/`)

Este documento desglosa línea por línea la lógica interna, decisiones de ingeniería y el libreto de sustentación para la carpeta `scripts/`. Con esto demostrarás ante el evaluador que conoces cada bandera, comando y truco técnico de Bash implementado.

---

## 1. Desglose Técnico: Los 5 Scripts Clave

### Script 1: `scripts/validate-params.sh` (Validación Shift-Left de Parámetros)
- **Problema que resuelve:** Problema #5 del PDF (Configuraciones inconsistentes editadas manualmente que rompían producción).
- **Lógica interna:**
  1. Lee el esquema formal [`infra/params/schema.json`](../infra/params/schema.json) que define los tipos, rangos numéricos y enums de los parámetros.
  2. Itera sobre los archivos de cada ambiente (`dev.json`, `staging.json`, `prod.json`).
  3. Ejecuta validación con `check-jsonschema` (con fallback a `python3 -c "import jsonschema"`).
  4. **Impacto:** Si un desarrollador pone `LogRetentionDays: -5` o un string en vez de número, el script bloquea el pipeline en **menos de 2 segundos** sin tocar AWS.

### Script 2: `scripts/deploy-frontend.sh` (Despliegue Atómico de SPA en S3 + CloudFront)
- **Problema que resuelve:** Entregable 3 del PDF (¿Cómo desplegar el frontend en S3 e invalidar CloudFront?).
- **Decisiones Senior de Ingeniería:**
  1. **Cero Hardcoding:** No tiene nombres de buckets ni IDs de CloudFront quemados en el código. Ejecuta `aws cloudformation describe-stacks` y extrae dinámicamente los valores desde los `Outputs` del stack.
  2. **Estrategia de Caché Dual (FinOps y Cero Downtime):**
     - **Paso A:** Sube los archivos estáticos con hash (`.js`, `.css`, imágenes) usando `--cache-control "public, max-age=31536000, immutable"`. Como tienen hash en el nombre, se guardan 1 año en los nodos de borde de CloudFront, ahorrando costos de transferencia y acelerando la carga.
     - **Paso B:** Sube `index.html` **al final** con `--cache-control "no-cache, no-store, must-revalidate"`. Esto garantiza que los navegadores siempre consulten la última versión sin que la web se rompa durante el despliegue (despliegue atómico).
  3. **Invalidación Selectiva:** Ejecuta `aws cloudfront create-invalidation` únicamente sobre `"/index.html"` y `"/"`. No invalida `/*`, manteniéndose dentro de las 1,000 invalidaciones mensuales gratuitas del Free Tier.

### Script 3: `scripts/smoke-test.sh` (Pruebas de Humo en Vivo y Negativas)
- **Problema que resuelve:** Problema #2 del PDF (Garantizar que lo desplegado funciona antes de promover de ambiente).
- **Decisiones Senior de Ingeniería:**
  1. Obtiene dinámicamente la URL de API Gateway y de CloudFront desde CloudFormation.
  2. Utiliza `curl -s -o /dev/null -w "%{http_code}"` para evaluar códigos HTTP puros.
  3. **Prueba 1 (Portal Web):** Consulta la raíz de CloudFront esperando `200 OK`.
  4. **Prueba 2 (Healthcheck API):** Consulta el endpoint ping esperando `200 OK`.
  5. **Prueba 3 (Creación Positiva):** Envía un `POST /api/v1/claims` con un payload sintético de siniestro y valida que retorne `201 Created` y un `claimId` válido.
  6. **Prueba 4 (Prueba Negativa de Seguridad):** Envía un `POST` con body vacío `{}` esperando un `400 Bad Request`. Demuestra que el backend rechaza datos corruptos. Si devuelve 500 o 200, la prueba falla.

### Script 4: `scripts/dora-metrics.sh` (Medición Real de DORA cruzando Git y CloudWatch)
- **Problema que resuelve:** Entregable 5 del PDF (Monitorear métricas DORA).
- **Decisiones Senior de Ingeniería:**
  1. **Cálculo Real de Lead Time:** Extrae el timestamp Unix del commit con `git log -1 --format=%ct` y lo resta del timestamp actual (`date +%s`). Convierte la diferencia a minutos reales.
  2. **Publicación a CloudWatch Metrics:** Ejecuta `aws cloudwatch put-metric-data --namespace SiniestrosDORA` enviando:
     - `DeploymentFrequency` (Counter)
     - `LeadTimeMinutes` (Valor en minutos reales del ciclo de entrega)
     - `ChangeFailureRate` (Porcentaje de fallos)
     - `MeanTimeToRestore` (Tiempo de recuperación ante incidentes)
  3. Alimenta directamente el tablero `ObservabilityDashboard` en CloudWatch.

### Script 5: `scripts/ai-devops-assistant.sh` (Inteligencia Artificial con Amazon Bedrock)
- **Problema que resuelve:** Entregable 6 del PDF (Integración de AI en el flujo DevOps).
- **Decisiones Senior de Ingeniería:**
  1. **Privacidad y Regulación SFC:** Antes de enviar logs a la IA, el script sanitiza el texto usando `sed` para eliminar tokens, contraseñas, correos y cédulas (PII).
  2. **Modelo Bedrock:** Utiliza `amazon.nova-micro-v1:0` vía AWS CLI (`aws bedrock-runtime converse`), garantizando que los datos no salgan de la nube de AWS y manteniendo el costo por debajo de $0.01 USD.
  3. **Modo `triage`:** Analiza reportes de escaneos y genera `security-summary.md` para el aprobador humano.
  4. **Modo `failure`:** Analiza la salida de error del pipeline, diagnostica la causa raíz y genera `ai-failure-analysis.md` con el comando exacto para corregir la falla.

### Script 6: `scripts/teardown.sh` (Destrucción Limpia y FinOps)
- **Problema que resuelve:** Entregable 6 del PDF (Estimación de costos y reproducibilidad).
- **Decisiones Senior de Ingeniería:**
  1. Un problema clásico de CloudFormation es que si un bucket S3 tiene archivos o versiones viejas, el `delete-stack` falla con `BucketNotEmpty`.
  2. `teardown.sh` consulta los buckets del stack, suspende el versionamiento y ejecuta `aws s3api delete-objects` para eliminar todas las versiones y marcadores de borrado en paralelo.
  3. Ejecuta `aws cloudformation delete-stack` y espera con `aws cloudformation wait stack-delete-complete`.

---

## 2. Libreto de Sustentación en Texto Corrido con Negritas (Para la Exposición)

*(Léelo cuando te pregunten por los scripts, o intercálalo en tu exposición para demostrar dominio profundo de la consola y automatización).*

> Un punto crítico que diseñamos para garantizar robustez en el pipeline fue **evitar scripts genéricos o comandos hardcodeados**. Cada script dentro de la carpeta **`scripts/`** implementa patrones avanzados de ingeniería Cloud y DevOps:
> 
> En primer lugar, **`scripts/validate-params.sh`** aplica validación **Shift-Left**: en lugar de esperar a que CloudFormation falle minutos después en AWS, el script toma los parámetros de cada ambiente y los valida localmente contra nuestro **`schema.json`** en menos de dos segundos, asegurando que nadie despliegue valores erróneos de retención o memoria.
> 
> En segundo lugar, **`scripts/deploy-frontend.sh`** resuelve el despliegue del portal web mediante una **estrategia de caché atómica**: el script consulta dinámicamente los *Outputs* de CloudFormation para no quemar nombres de buckets en código; luego sube los assets estáticos con hash bajo una política **`immutable` de un año en CloudFront**, y sube el archivo **`index.html` al final con cabecera `no-cache`**, ejecutando una invalidación selectiva únicamente sobre la raíz y el index. Esto garantiza que ningún usuario reciba versiones rotas del portal web mientras se despliega y evita sobrecostos por invalidaciones masivas en CloudFront.
> 
> En tercer lugar, **`scripts/smoke-test.sh`** no se limita a un simple ping: ejecuta pruebas funcionales y **pruebas negativas de seguridad con `curl`**, validando que el registro de un siniestro devuelva un código **`201 Created`**, pero también comprobando que una petición vacía sea rechazada con un código **`400 Bad Request`**, asegurando que los validadores de API Gateway y Lambda respondan correctamente antes de promover el build.
> 
> En cuarto lugar, **`scripts/dora-metrics.sh`** no utiliza datos simulados: calcula el **Lead Time for Changes real** extrayendo el timestamp Unix del commit con **`git log -1 --format=%ct`** y comparándolo contra el segundo exacto del despliegue exitoso, publicando métricas nativas a CloudWatch con **`put-metric-data`** para alimentar el dashboard ejecutivo.
> 
> Y finalmente, **`scripts/ai-devops-assistant.sh`** implementa nuestros dos casos de uso de **Amazon Bedrock**: antes de enviar cualquier información a la IA, el script **sanitiza los logs eliminando datos sensibles y PII con `sed`**, garantizando estricto cumplimiento con la **Superintendencia Financiera**, para luego consultar el modelo **`nova-micro-v1`**, entregando resúmenes ejecutivos de seguridad y diagnóstico de fallos con comandos de remediación en segundos. Con estos scripts garantizamos un flujo reproducible, seguro y libre de intervención manual.
