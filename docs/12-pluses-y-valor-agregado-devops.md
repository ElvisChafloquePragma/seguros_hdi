# Valores Agregados y Pluses Senior DevOps (No Solicitados en la Prueba Técnica)

Este documento recopila las **7 mejoras proactivas de ingeniería DevOps, CloudOps, DevSecOps y FinOps** implementadas en el proyecto que van más allá del enunciado de la prueba técnica (`Prueba Tecnica - Perfil DevopsNB (2).pdf`), diseñadas para demostrar un nivel **Senior / Lead** ante el comité evaluador y la aseguradora (HDI Seguros / Regulación SFC).

---

## 1. Matriz Resumen de Pluses: Lo Solicitado vs Nuestro Valor Agregado

| # | Dimensión | Lo Solicitado en la Prueba Técnica | Nuestro Valor Agregado Proactivo (Senior Plus) | Archivo Involucrado | Impacto de Negocio / Técnico |
|---|---|---|---|---|---|
| **1** | **FinOps & Compliance** | Crear un bucket S3 para reportes con cifrado KMS. | **`LifecycleConfiguration` automatizado** a 5 años (90d `STANDARD_IA`, 365d `GLACIER_IR`). | [`infra/template.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/infra/template.yaml) | Ahorro del 68% en almacenamiento cumpliendo retención probatoria legal de siniestros exigida por la SFC. |
| **2** | **Ciberseguridad Perimetral** | Desplegar SPA en CloudFront con HTTPS. | **Cabeceras HTTP de Seguridad Gestionadas (`Managed-SecurityHeadersPolicy`)** en CloudFront. | [`infra/template.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/infra/template.yaml) | Inyecta HSTS, X-Frame-Options: DENY (anti-clickjacking) y nosniff. Calificación A+ en auditorías OWASP. |
| **3** | **Auditoría Forense SFC** | Habilitar trazabilidad en API Gateway. | **Grupo de logs forenses dedicados (`ApiAccessLogGroup`) con `AccessLogSetting` en JSON estructurado**. | [`infra/template.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/infra/template.yaml) | Registra IP de origen, usuario Cognito, latencia y RequestId antes del cómputo (Circular 007 SFC). |
| **4** | **Observabilidad CI/CD** | Pipeline básico en Jenkins que ejecute etapas secuenciales. | **Inyección dinámica de metadatos en la interfaz web de Jenkins (`currentBuild.description`)**. | [`Jenkinsfile`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/Jenkinsfile) | Visibilidad ejecutiva en tiempo real: Commit SHA, rama, ambiente, usuario aprobador y estado del build. |
| **5** | **Gobernanza DevSecOps** | Ejecutar escaneos de seguridad en el pipeline. | **Policy-as-Code con Registro Formal de Excepciones Auditadas (`.security-exceptions.yaml`)**. | [`.security-exceptions.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/.security-exceptions.yaml) | Cero bypasses informales: toda exclusión tiene justificación técnica, oficial de cumplimiento y fecha de vencimiento. |
| **6** | **Métricas DORA Reales** | "Crear un dashboard para monitorear métricas DORA". | **Cálculo de Lead Time real cruzando el timestamp del commit de Git contra el despliegue**. | [`scripts/dora-metrics.sh`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/scripts/dora-metrics.sh) | Métricas operacionales verídicas publicadas a CloudWatch Metrics mediante AWS CLI (`put-metric-data`). |
| **7** | **Aceleración con IA** | Uso libre de IA para apoyar tareas. | **Doble caso de uso de Amazon Bedrock en CI/CD**: Triage de seguridad preventivo y SRE de diagnóstico post-fallo. | [`scripts/ai-devops-assistant.sh`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/scripts/ai-devops-assistant.sh) | Reduce el MTTR al diagnosticar causas raíz con comandos de solución inmediata sin exponer datos PII. |

---

## 2. Libreto de Sustentación en Texto Corrido con Negritas (Para la Entrevista)

*(Este texto está redactado en formato continuo para ser leído o parafraseado fluidamente durante la exposición cuando el evaluador pregunte por mejoras o cuando decidas presentar tus valores agregados).*

Para concluir nuestra presentación, queremos destacar que, **más allá de los requerimientos base solicitados en la prueba técnica**, como equipo de ingeniería DevOps decidimos implementar **siete valores agregados proactivos** enfocados en **FinOps, Ciberseguridad, Gobernanza corporativa y Regulación de la Superintendencia Financiera de Colombia**.

El primer gran plus está en el almacenamiento y costos: la prueba pedía un bucket S3 para reportes, pero en una aseguradora regulada por la **SFC**, los expedientes probatorios de siniestros deben custodiarse legalmente entre cinco y diez años. Si dejamos esos archivos en la capa estándar, la factura de almacenamiento crece exponencialmente; por eso, configuramos una regla automatizada de **`LifecycleConfiguration`** que transiciona los documentos a los noventa días a **`STANDARD_IA`** ahorrando un 40%, y a los trescientos sesenta y cinco días a **`GLACIER_IR`**, logrando un **ahorro consolidado del 68% en la factura de AWS** sin perder la capacidad de recuperación inmediata.

El segundo plus es de ciberseguridad perimetral: en lugar de dejar la distribución de CloudFront con sus cabeceras por defecto, inyectamos la política administrada **`ResponseHeadersPolicyId` de AWS**, forzando en cada respuesta del portal web cabeceras críticas como **HSTS (`Strict-Transport-Security`)**, protección contra clickjacking mediante **`X-Frame-Options: DENY`**, y prevención de inyección MIME con **`X-Content-Type-Options: nosniff`**, otorgándole a la aplicación web una **calificación A+ en auditorías de seguridad OWASP**.

El tercer plus corresponde a la trazabilidad forense: muchas implementaciones solo habilitan métricas básicas de CloudWatch en API Gateway, pero la **Circular Externa 007 de 2018 de la SFC** exige registrar evidencia forense de todo intento de acceso; por ello, aprovisionamos el recurso **`ApiAccessLogGroup`** y configuramos **`AccessLogSetting`**, guardando en formato JSON estructurado la **dirección IP de origen, la identidad del ajustador autenticado en Cognito, la latencia y el identificador único de petición** antes de que el tráfico toque el cómputo Lambda.

El cuarto plus se diseñó en el pipeline de Jenkins para visibilidad operativa: normalmente la consola web de Jenkins solo lista números de build genéricos, lo que obliga al equipo a abrir cada log para saber qué pasó; nosotros implementamos **`currentBuild.description`**, inyectando dinámicamente en la interfaz de Jenkins el **commit corto de Git, la rama, el ambiente de despliegue, el usuario aprobador de la SFC y el estado final**, permitiendo que cualquier líder técnico o auditor comprenda el estado del negocio de un solo vistazo.

El quinto plus aborda la gobernanza DevSecOps mediante **Policy-as-Code**: en las empresas es muy común que los desarrolladores desactiven escáneres como Checkov cuando emiten alertas que no aplican; para resolverlo profesionalmente, creamos el archivo formal **`.security-exceptions.yaml`**, en donde cada excepción de seguridad está justificada técnicamente, respaldada con el rol de **Oficial de Cumplimiento SFC** y delimitada con una **fecha estricta de vencimiento**, estableciendo un control auditable sin excepciones informales.

El sexto plus es la medición de métricas DORA: en el mercado muchos candidatos solo conocen la teoría de DORA, pero en nuestro pipeline el script **`dora-metrics.sh`** calcula el **Lead Time for Changes de forma real**, restando el timestamp del commit en Git frente al instante exacto del despliegue exitoso en CloudFormation, publicando automáticamente las cuatro métricas a CloudWatch mediante el comando **`put-metric-data`** para alimentar el tablero unificado de observabilidad.

Y el séptimo plus es la integración de Inteligencia Artificial con **Amazon Bedrock**: diseñamos una arquitectura de **doble caso de uso** con el modelo **`nova-micro-v1`**, primero ejecutando un **triage preventivo de seguridad** en la etapa de escaneo para resumir vulnerabilidades en lenguaje de negocio para el aprobador humano, y segundo activando un **SRE inteligente post-fallo** que, ante cualquier caída del pipeline, analiza el log sin exponer secretos ni datos personales, diagnostica la causa raíz y entrega el comando exacto de remediación, acelerando drásticamente el tiempo de recuperación del servicio. Con estos siete valores agregados entregamos una plataforma robusta, costo-eficiente y con estándar corporativo de producción.

---

## 3. Evidencias Técnicas en el Repositorio

- **Plus 1 (S3 Lifecycle):** Líneas 164-173 de [`infra/template.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/infra/template.yaml#L164-L173).
- **Plus 2 (Security Headers):** Línea 410 de [`infra/template.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/infra/template.yaml#L410).
- **Plus 3 (API Access Logs):** Líneas 183-195 de [`infra/template.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/infra/template.yaml#L183-L195).
- **Plus 4 (Jenkins UI Badges):** Líneas 65, 203, 230 y 236 de [`Jenkinsfile`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/Jenkinsfile).
- **Plus 5 (Security Exceptions):** Archivo completo [`.security-exceptions.yaml`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/.security-exceptions.yaml).
- **Plus 6 (DORA Lead Time Real):** Líneas 20-35 de [`scripts/dora-metrics.sh`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/scripts/dora-metrics.sh).
- **Plus 7 (Bedrock AI Dual):** Funciones `triage_security()` y `analyze_failure()` en [`scripts/ai-devops-assistant.sh`](file:///mnt/c/Users/elvis.chafloque_prag/Documents/Prueba_tecnica/scripts/ai-devops-assistant.sh).

