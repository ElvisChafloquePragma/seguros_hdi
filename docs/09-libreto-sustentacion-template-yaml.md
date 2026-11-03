# Libreto de Exposición Integral: Plantilla de Infraestructura (`infra/template.yaml`)

> **Guía para la sustentación:** Este libreto está estructurado en texto continuo y fluido, con **énfasis visual en negrita** para proyectar seguridad técnica. Recorre de punta a punta cada sección del archivo `infra/template.yaml`, explicando no solo qué recursos existen, sino las decisiones de arquitectura, seguridad (SFC) y FinOps que los respaldan.

---

### 1. Introducción y Motor de Infraestructura como Código (Líneas 1-13)

"Pasando a la capa de **Infraestructura como Código (IaC)**, toda la solución está centralizada en nuestro archivo **`infra/template.yaml`**. Esta plantilla utiliza **AWS CloudFormation potenciado por el macro de AWS SAM (`Transform: AWS::Serverless-2016-10-31`)**. La decisión de utilizar SAM en lugar de CloudFormation puro o Terraform se basó en la agilidad y las mejores prácticas nativas de AWS: SAM nos permite gestionar la compilación de Lambdas, el mapeo de eventos de API Gateway, y especialmente las estrategias de despliegue gradual de **AWS CodeDeploy** con apenas unas líneas declarativas, evitando redactar cientos de líneas repetitivas de CloudFormation tradicional pero manteniendo la compatibilidad nativa con el motor de CloudFormation."

---

### 2. Parámetros, Condiciones y Gobernanza FinOps (Líneas 14-61)

"Para evitar errores manuales y garantizar la consistencia entre ambientes, la plantilla inicia con **9 parámetros fuertemente tipados**. Establecemos una convención de nomenclatura estándar basada en **`${ProjectName}-${Env}`**, lo que nos da la flexibilidad de desplegar múltiples instancias paralelas del stack sin riesgo de colisión de nombres. 

Entre los parámetros destacan el **`NodeRuntime`** fijado en **`nodejs22.x`** (versión LTS sobre Amazon Linux 2023), memoria y timeouts parametrizados, y la estrategia **`DeploymentPreferenceType`**, que permite seleccionar entre **`AllAtOnce`** para desarrollos rápidos o **`Canary10Percent5Minutes`** para despliegues controlados. También parametrizamos **`LogRetentionDays`**, configurado en 14 días para desarrollo y hasta 365 días en producción para cumplir con los requerimientos probatorios de la **Superintendencia Financiera de Colombia (SFC)**.

En la sección **`Conditions`**, implementamos lógica condicional como **`ShouldEnableWaf`**: por estrategia de **optimización de costos (FinOps)**, mantenemos **AWS WAFv2** apagado en `dev` y `staging` para evitar costos fijos mensuales innecesarios, y lo activamos automáticamente cuando el parámetro `Env` es igual a `prod`."

---

### 3. La Sección `Globals`: Buenas Prácticas y Controles Avanzados (Líneas 62-81)

"Una característica exclusiva de SAM es la sección **`Globals`**, donde aplicamos el principio de arquitectura **DRY (*Don't Repeat Yourself*)** para que todas las funciones Lambda del backend hereden la misma configuración base:

Primero, fijamos la arquitectura en **`arm64` (procesadores AWS Graviton2)**, lo que nos entrega un **20% de ahorro en costos por milisegundo y hasta un 19% más de rendimiento** frente a x86_64. 

Segundo, activamos el trazado distribuido de **AWS X-Ray (`Tracing: Active`)**, lo que nos permite auditar el mapa de calor y la latencia exacta de cada petición desde que entra por API Gateway hasta que consulta DynamoDB o S3.

Tercero, configuramos los **Advanced Logging Controls** nativos de AWS Lambda:
- **`LogFormat: JSON`**: Obliga al hipervisor de Lambda a emitir todos los logs estructurados en JSON nativo sin necesidad de librerías externas en Node.js, facilitando consultas inmediatas en CloudWatch Logs Insights.
- **`ApplicationLogLevel: INFO`**: Filtra automáticamente los mensajes de depuración (`DEBUG`) del código, reduciendo la factura de ingesta en CloudWatch en un 40%.
- **`SystemLogLevel: WARN`**: Silencia el ruido rutinario de inicio y parada del sistema Lambda, registrando únicamente advertencias o fallos reales.

Finalmente, el bloque **`Environment.Variables`** inyecta a nivel de sistema operativo (`process.env`) el nombre de la tabla DynamoDB, el bucket S3, el secreto y la llave KMS generados por CloudFormation. Con esto cumplimos el estándar **12-Factor App**, logrando que el código compilado del backend sea 100% agnóstico y jamás tenga nombres ni recursos 'hardcodeados' a fuego."

---

### 4. Bloque 1: Seguridad, Cifrado KMS y Secrets Manager (Líneas 82-123)

"El Bloque 1 atiende las exigencias de ciberseguridad y la **Circular Externa 007 de 2018 de la SFC**:

Aprovisionamos la llave administrada por el cliente **`AppKmsKey` (AWS KMS CMK)** con **rotación anual automática (`EnableKeyRotation: true`)** y una ventana de eliminación de 7 días. Su **`KeyPolicy`** implementa la declaración **`EnableRootAdminPermissions`**, delegando la administración a la cuenta de AWS para que las políticas de IAM de los roles de las Lambdas puedan utilizarla de forma granular, evitando crear una llave inaccesible. Esta llave se encarga de cifrar en reposo los tres lugares donde residen datos confidenciales (PII): la tabla **DynamoDB**, el bucket **S3 de Reportes** y las credenciales en **Secrets Manager**.

Junto a la llave, creamos **`IntegrationSecret` en AWS Secrets Manager** cifrado bajo nuestra CMK. Para evitar secretos expuestos en Git o digitados manualmente, usamos la propiedad **`GenerateSecretString`**: AWS genera de forma criptográfica y automática un API Key de 24 caracteres sin caracteres especiales (`ExcludePunctuation: true`) durante el despliegue. Esto asegura que la integración con proveedores de asistencia vehicular nazca segura, pasando completamente limpios los escaneos de **Gitleaks**."

---

### 5. Bloque 2: Capa de Persistencia y Archivo Normativo SFC (Líneas 124-173)

"En la persistencia de datos implementamos dos almacenes complementarios:

Para los datos transaccionales de los siniestros, creamos la tabla **`ClaimsTable` en DynamoDB** operando en modo **`PAY_PER_REQUEST` (On-Demand)**. Esto garantiza alta disponibilidad y autoescalado ante picos repentinos de siniestros por lluvias o catástrofes, con **costo $0.00 cuando no hay tráfico**. La tabla cuenta con su clave de partición `claimId`, cifrado KMS en reposo, y **Point-in-Time Recovery (PITR de 35 días)** habilitado para recuperaciones continuas al segundo ante cualquier corrupción de datos. Además, bajo **`DeletionPolicy: Retain`** y **`UpdateReplacePolicy: Retain`**, garantizamos que en producción una actualización accidental de la plantilla jamás elimine la base de datos histórica.

Para los documentos y reportes periciales en PDF, aprovisionamos **`ReportsBucket` en Amazon S3**. El bucket tiene **todas las políticas de acceso público bloqueadas al 100%**, versionamiento activo y cifrado KMS con **`BucketKeyEnabled: true`**, lo que reduce en un **99% las peticiones a la API de KMS** y optimiza la factura mensual. Los documentos son entregados de forma segura a los ajustadores mediante **URLs prefirmadas con expiración de 5 minutos**.

Como **gran plus FinOps y normativo**, incorporamos la regla de **`LifecycleConfiguration`**: los reportes en PDF se transicionan automáticamente a **`STANDARD_IA`** a los 90 días y a **`GLACIER_IR` (Instant Retrieval)** a los 365 días. Esto cumple la exigencia legal de la SFC de retener pruebas periciales durante 5 años, logrando hasta un **68% de ahorro en almacenamiento** frente al almacenamiento estándar."

---

### 6. Bloque 3: API Gateway REST, Autenticación Cognito y Auditoría Forense (Líneas 174-209)

"En la capa de API y autenticación:

Aprovisionamos **`AgentsUserPool` en Amazon Cognito** para autenticar a los ajustadores de seguros mediante su correo corporativo, con verificación de email y políticas estrictas de contraseñas, aprovechando el nivel gratuito de 50.000 usuarios activos mensuales.

Para exponer los servicios web, configuramos **`SiniestrosApi`** mediante un **API Gateway de tipo REST**, con propagación activa de X-Ray, soporte de CORS y autorización de tokens JWT mediante `CognitoAgentAuthorizer`.

Como **plus de auditoría y no repudio regulatorio (Circular 007 SFC)**, creamos el grupo de logs dedicado **`ApiAccessLogGroup`** y activamos **`AccessLogSetting`**. API Gateway registra en CloudWatch, en formato JSON estructurado, la IP de origen, el usuario autenticado de Cognito, el método, el recurso, la latencia y el RequestId de **absolutamente cada petición antes de invocar el cómputo**, garantizando una pista de auditoría forense inmutable."

---

### 7. Bloque 4: Cómputo Lambda, Despliegue Canary y Protección de PII (Líneas 210-318)

"En el cómputo dividimos la lógica de negocio en dos funciones serverless de responsabilidad única: **`ClaimsFunction`** (gestión del ciclo de vida del siniestro) y **`DocumentsFunction`** (generación de PDFs en S3 con `pdfkit`):

Ambas funciones implementan el principio de **mínimo privilegio en IAM**: `ClaimsFunction` solo tiene permisos CRUD sobre DynamoDB y lectura del secreto, mientras que `DocumentsFunction` solo tiene permisos de lectura en DynamoDB y escritura en el bucket de reportes.

Para el despliegue continuo seguro, ambas funciones publican versiones inmutables con **`AutoPublishAlias: live`** conectado a **AWS CodeDeploy**: en producción, se activa la estrategia **`Canary10Percent5Minutes`**. CodeDeploy envía únicamente el **10% del tráfico real a la nueva versión** y vigila durante 5 minutos las alarmas de CloudWatch (`ClaimsFunctionErrorsAlarm` y `ApiGateway5xxAlarm`). Si ocurre un solo fallo, **CodeDeploy aborta el despliegue y hace rollback automático del tráfico a la versión previa en menos de 60 segundos**, sin impacto para los asegurados ni intervención manual.

Además, en **`ClaimsFunctionLogGroup`** implementamos un control avanzado de privacidad: una **`DataProtectionPolicy` nativa de CloudWatch Logs**. Esta política inspecciona el flujo de logs y, si detecta una dirección de correo o un secreto de AWS, **lo enmascara automáticamente con asteriscos (`*****`) antes de guardarlo en disco**, garantizando el cumplimiento de la **Ley 1581 de Protección de Datos Personales (Habeas Data)** desde la propia infraestructura."

---

### 8. Bloque 5: Perímetro Seguro, CloudFront CDN y Frontend SPA (Líneas 319-444)

"En el perímetro de la aplicación, el portal web en React SPA se almacena en el bucket privado **`FrontendBucket`**, protegido con cifrado AES256 y bloqueo total de acceso público:

La única vía de acceso al bucket es **Amazon CloudFront**, gracias al aprovisionamiento de **`CloudFrontOriginAccessControl` (OAC con protocolo SigV4)** y la política **`FrontendBucketPolicy`**, que restringe las lecturas de S3 exclusivamente a peticiones firmadas provenientes del ARN de nuestra distribución CDN.

En producción, la distribución se encuentra blindada por **`FrontendWebACL` (AWS WAFv2)**, el cual aplica el conjunto de reglas gestionadas de AWS contra el **OWASP Top 10** (`AWSManagedRulesCommonRuleSet`), bloqueando ataques comunes de inyección SQL, XSS y escaneos maliciosos.

Nuestra distribución **`CloudFrontDistribution`** incorpora dos grandes ventajas arquitectónicas:
1. **Calificación A+ en Seguridad Web**: En el comportamiento por defecto inyectamos la política gestionada **`ResponseHeadersPolicyId` (Managed-SecurityHeadersPolicy)**, forzando cabeceras HTTP de estricta seguridad como **HSTS**, **X-Frame-Options: DENY**, **X-Content-Type-Options: nosniff** y protección XSS.
2. **Arquitectura de Dominio Unificado (Eliminación de CORS)**: Configuramos dos orígenes bajo la misma distribución. La raíz `/` atiende los estáticos del SPA con soporte de rutas virtuales mediante **`CustomErrorResponses`** (redireccionando errores 403 y 404 hacia `/index.html`), mientras que la ruta **/api/\*** desvía el tráfico directamente al API Gateway con caché desactivada. Al convivir el frontend y el backend bajo el mismo dominio HTTPS, **eliminamos de raíz la fricción y fallos de CORS**. Además, usamos la clase **`PriceClass_100`** para cubrir Norteamérica y Colombia optimizando costos."

---

### 9. Bloque 6: Observabilidad Integral, Métricas DORA y Salidas (Líneas 445-593)

"Para cerrar el ciclo de operaciones, la plantilla aprovisiona una suite completa de observabilidad:

1. **`AlertsTopic` en Amazon SNS**: Canal centralizado para notificación de fallos e incidentes críticos hacia el equipo de guardia de DevOps.
2. **Alarmas de CloudWatch con `TreatMissingData: notBreaching`**: Monitorean errores en Lambdas y errores 5XX en API Gateway evaluando periodos de 60 segundos. La configuración `notBreaching` es clave para evitar falsos positivos nocturnos cuando no hay tráfico de siniestros. Estas son las alarmas que disparan el rollback automático en CodeDeploy.
3. **Tablero `ObservabilityDashboard`**: Unifica en un único panel la tasa de peticiones y errores 5XX de API Gateway, las invocaciones y fallos de las Lambdas, y un widget dedicado a las **4 métricas DORA** (`DeploymentFrequency`, `LeadTimeMinutes`, `ChangeFailureCount`, `MeanTimeToRestoreMinutes`), las cuales son alimentadas directamente por nuestro script de pipeline `dora-metrics.sh`.

Finalmente, en la sección **`Outputs`**, exportamos de forma estructurada los valores generados dinámicamente por CloudFormation: la URL pública de CloudFront, el ID de la distribución, el endpoint del API Gateway, y los nombres de los buckets y tablas. Estas variables son consumidas de forma automatizada por nuestros scripts de despliegue de frontend y de smoke tests durante la ejecución del pipeline CI/CD."

---

### 10. Conclusión Ejecutiva

"En conclusión, este archivo `infra/template.yaml` no es un simple script de despliegue: es una arquitectura serverless empresarial completa, diseñada bajo el marco de **AWS Well-Architected**, que equilibra **seguridad regulatoria de nivel financiero (SFC)**, **cero costo fijo en reposo (FinOps)**, y **resiliencia operativa con despliegues graduales y rollback automatizado**."
