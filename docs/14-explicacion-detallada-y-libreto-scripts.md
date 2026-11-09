# Libreto Maestro de Exposición: Los 6 Scripts de Automatización (`scripts/`)

> **Tiempo estimado de exposición continua:** ~3 minutos (~520 palabras).  
> **Cómo exponerlo:** Muéstralo en tu editor de código recorriendo la carpeta `scripts/`. Proyecta seguridad técnica y convicción en las palabras en **negrita**.

---

## 🎙️ Libreto Principal de Sustentación Continua

"Pasando ahora a la capa de automatización en la carpeta **`scripts/`**, decidimos desacoplar toda la lógica operativa del `Jenkinsfile` modularizándola en **seis scripts Bash independientes**. Todos cuentan con la directiva **`set -e`** para garantizar tolerancia cero a fallos: ante cualquier error no controlado, la ejecución se aborta de inmediato evitando estados inconsistentes o despliegues a medias:

---

### 1. Validación Temprana (`validate-params.sh`)
En la Etapa 2 del pipeline aplicamos el principio **Shift-Left**: antes de gastar recursos de cómputo en AWS o compilar, ejecutamos **`validate-params.sh`**. Este script itera sobre `dev.json`, `staging.json` y `prod.json` y los valida contra nuestro contrato tipado en `schema.json` usando **`check-jsonschema`**. En solo dos segundos aseguramos que retenciones de logs, llaves KMS y tags cumplan estrictamente la norma, cancelando el pipeline de forma preventiva si un desarrollador cometió un error tipográfico.

---

### 2. Despliegue de Frontend y Caché Inteligente (`deploy-frontend.sh`)
Tras aprovisionar la infraestructura con SAM, ejecutamos **`deploy-frontend.sh`**. Este script resuelve el desafío de distribución en Single Page Applications: consulta dinámicamente los nombres de recursos en CloudFormation; sincroniza los archivos `.js` y `.css` versionados con **caché inmutable de un año** en S3; sube el **`index.html` con política estricta de `no-cache`**; y finalmente ejecuta una **invalidación atómica en CloudFront sobre `/index.html`**. En vez de invalidar con comodín `/*` —lo cual destruiría la caché global y generaría latencias—, purgar solo el index toma cinco segundos, garantiza **cero tiempo de inactividad** y se mantiene 100% dentro del Free Tier mensual de AWS.

---

### 3. Pruebas de Humo en Vivo (`smoke-test.sh`)
Como las pruebas unitarias corren con mocks en memoria y no detectan errores de permisos IAM ni caídas de red, implementamos **`smoke-test.sh`**. En menos de tres segundos, ejecuta cuatro llamadas en vivo con **`curl --fail`** contra el API Gateway: radica un siniestro en DynamoDB (`POST /claims`), lo consulta por ID (`GET`), actualiza su estado (`PATCH`) y genera el reporte PDF en S3 cifrado con KMS (`POST /documents/report`). Si cualquiera de los cinco microservicios falla o arroja un código 4XX o 5XX, el pipeline se detiene al instante.

---

### 4. Observabilidad de Entrega Continua (`dora-metrics.sh`)
Para medir objetivamente la madurez operativa del equipo, **`dora-metrics.sh`** captura las **cuatro métricas DORA** y las publica en Amazon CloudWatch bajo el namespace `SiniestrosDORA`:
* Calcula el **Lead Time real** restando matemáticamente la hora del último commit en Git (`git log -1 --format=%ct`) contra la hora de finalización del despliegue. En `dev` mide el ciclo técnico de compilación (~3 minutos), y en `prod` audita el ciclo completo incluyendo el tiempo del comité de aprobación regulatoria SFC.
* Registra la **Frecuencia de Despliegue** y la **Tasa de Fallos (CFR)** según el resultado de Jenkins.
* Y en **MTTR**, refleja nuestra capacidad de restauración automática: gracias al despliegue Canary y alarmas de CloudWatch evaluadas cada 60 segundos, **AWS CodeDeploy revierte el 100% del tráfico a la versión sana en apenas 75 segundos** sin intervención humana.

---

### 5. Asistente con IA Generativa (`ai-devops-assistant.sh`)
Como valor diferencial de innovación, integramos el pipeline con **Amazon Bedrock** utilizando el modelo fundacional **Nova Micro (`amazon.nova-micro-v1:0`)**:
* En modo **`triage`**, analiza los escaneos de Gitleaks, Semgrep, Trivy y Checkov, condensándolos en un dictamen ejecutivo en Markdown para el aprobador del gate de Producción.
* En modo **`failure`**, si una etapa falla, diagnostica la causa raíz y entrega el comando exacto para remediar el incidente.
* Cuenta con un mecanismo de respaldo automático (*fallback*) para no interrumpir el pipeline si el servicio de IA no estuviese disponible.

---

### 6. Destrucción Limpia y FinOps (`teardown.sh`)
Finalmente, para cumplir con el gobierno de costos (FinOps), **`teardown.sh`** permite destruir la infraestructura bajo demanda. Su gran valor técnico es que purga automáticamente tanto objetos normales como **versiones históricas y marcadores de borrado** en los buckets S3 versionados antes de invocar `aws cloudformation delete-stack`, garantizando que CloudFormation nunca falle al eliminar el stack y dejando la cuenta en **costo cero absoluto**."

---

## ⚡ Versión Flash / Elevator Pitch (30 segundos)

> *"Nuestra carpeta `scripts/` implementa una cadena de entrega continua integral:  
> 1. **Shift-Left:** Validación de parámetros con `check-jsonschema`.  
> 2. **Despliegue SPA:** S3 con caché inmutable e invalidación atómica en CloudFront.  
> 3. **Verificación en vivo:** Smoke tests con `curl --fail` sobre DynamoDB y S3.  
> 4. **Métricas DORA:** Lead Time real con `git log` y publicación nativa en CloudWatch.  
> 5. **IA DevSecOps:** Triaje y análisis de causa raíz con Amazon Bedrock.  
> 6. **FinOps:** Teardown automatizado de buckets versionados para costo cero."*

---

## 🛡️ Preguntas Trampa del Jurado y Respuestas Maestras

#### 1. *"¿Por qué invalidaron solo `/index.html` y no `/*` en CloudFront?"*
* **Respuesta:** *"Porque en React/Vite los archivos `.js` y `.css` tienen un hash único en su nombre (`app-a1b2c3.js`). Al ser nombres nuevos, CloudFront los descarga frescos automáticamente. El único archivo con nombre estático es `index.html`. Invalidar solo el index toma 3 segundos, evita la saturación de tráfico hacia S3 (*cache stampede*) y entra 100% gratis dentro de las 1,000 invalidaciones mensuales de AWS."*

#### 2. *"¿Por qué el Lead Time en Producción no es de 3 minutos como en Dev?"*
* **Respuesta:** *"Porque por exigencia regulatoria de la Superintendencia Financiera de Colombia (SFC), en producción existe el principio de Segregación de Funciones y Cuatro Ojos (Etapa 7 de Jenkins). El Lead Time de DORA en Producción mide el tiempo total desde el commit hasta que el usuario recibe el cambio, absorbiendo de forma transparente el tiempo de revisión humana del dictamen de seguridad."*

#### 3. *"¿Cómo garantizan que el script de Teardown no falle si los buckets tienen versionamiento?"*
* **Respuesta:** *"Un `aws s3 rm --recursive` convencional falla si hay versionamiento porque no elimina versiones anteriores ni marcadores de borrado. Nuestro script consulta `list-object-versions` y ejecuta `delete-objects` sobre `Versions` y `DeleteMarkers` antes de llamar a `delete-stack`, asegurando una eliminación limpia al 100%."*
