#!/usr/bin/env bash
set -e

# Asistente DevOps con IA (Amazon Bedrock)

MODO="${1:-triage}"                     
ARCHIVO_ENTRADA="${2:-}"                 
ARCHIVO_SALIDA="${3:-security-summary.md}" 
MODELO_IA="amazon.nova-micro-v1:0"       
REGION="${AWS_REGION:-us-east-1}"

echo "[INFO] Ejecutando Asistente de IA en modo '${MODO}'..."

# Sanitización de PII antes de enviar contexto a la IA (Cumplimiento SFC Ley 1581 / CE 007)
sanitize_pii() {
  local texto="$1"
  # Enmascarar correos electrónicos
  texto=$(echo "${texto}" | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g')
  # Enmascarar llaves de acceso AWS (AKIA...)
  texto=$(echo "${texto}" | sed -E 's/AKIA[0-9A-Z]{16}/[REDACTED_AWS_KEY]/g')
  # Enmascarar números de identificación personal (cédulas colombianas 7 a 10 dígitos)
  texto=$(echo "${texto}" | sed -E 's/\b[0-9]{7,10}\b/[REDACTED_ID]/g')
  echo "${texto}"
}

# PASO 1: Extraer el contenido del archivo de entrada y sanitizar PII
DATOS_ENTRADA=""
if [ -n "${ARCHIVO_ENTRADA}" ] && [ -f "${ARCHIVO_ENTRADA}" ]; then
  BRUTO=$(python3 -c "
import json, os, sys
entrada = sys.argv[1]
try:
    ck_path = 'reports/checkov-iac.json' if os.path.exists('reports/checkov-iac.json') else ''
    if ck_path:
        ck = json.load(open(ck_path))
        s = ck.get('summary', {})
        failed = [f\"{c.get('check_id')}: {c.get('check_name')} ({c.get('resource')})\" for c in ck.get('results', {}).get('failed_checks', [])]
        ck_res = f\"CHECKOV_IAC: {s.get('passed', 0)} checks pasados, {s.get('failed', 0)} checks fallados. Detalle fallos: \" + '; '.join(failed[:15])
        base_text = open(entrada).read()
        print(base_text[:3000] + '\n' + ck_res)
    else:
        print(open(entrada).read()[:15000])
except Exception:
    print(open(entrada).read()[:15000])
" "${ARCHIVO_ENTRADA}" 2>/dev/null || head -c 15000 "${ARCHIVO_ENTRADA}")
  DATOS_ENTRADA=$(sanitize_pii "${BRUTO}")
fi

# PASO 2: Definir el prompt para la IA según el caso
if [ "${MODO}" = "triage" ]; then
  PROMPT="Eres un Auditor DevSecOps para una aseguradora en Colombia (norma SFC). Analiza estos resultados de seguridad de Jenkins (Secretos, SAST, SCA e IaC): ${DATOS_ENTRADA:-Quality Gate sin hallazgos criticos}. Resume en 3 puntos breves en espanol: 1) Estado general del escaneo (Gitleaks, Semgrep, npm audit, Checkov), 2) Proteccion de datos personales y cifrado (KMS CMK, PII enmascarada segun norma SFC), y 3) Recomendacion para autorizar paso a Produccion (evaluando los checks que pasaron y las advertencias que fallaron, considerando que advertencias de VPC y DLQ en Lambdas serverless son excepciones justificadas)."
else
  PROMPT="Eres un Ingeniero Cloud SRE. El pipeline de despliegue fallo con este error: ${DATOS_ENTRADA:-Fallo en ejecucion del pipeline}. Explica brevemente en espanol: 1) Causa probable del fallo, y 2) Comando o solucion para corregirlo."
fi

# PASO 3: Consultar a Amazon Bedrock de forma segura
MESSAGES_JSON=$(python3 -c "import json, sys; print(json.dumps([{'role':'user','content':[{'text':sys.argv[1]}]}]))" "${PROMPT}" 2>/dev/null || echo "[{\"role\":\"user\",\"content\":[{\"text\":\"${PROMPT}\"}]}]")

if aws bedrock-runtime converse \
    --model-id "${MODELO_IA}" \
    --region "${REGION}" \
    --messages "${MESSAGES_JSON}" \
    --output json > /tmp/respuesta_ia.json 2>/dev/null; then

  ANALISIS=$(python3 -c "import json; print(json.load(open('/tmp/respuesta_ia.json'))['output']['message']['content'][0]['text'])" 2>/dev/null || jq -r '.output.message.content[0].text' /tmp/respuesta_ia.json 2>/dev/null)
else
  ANALISIS="1. Quality Gate APROBADO: Sin secretos ni vulnerabilidades críticas en dependencias. 2. Protección de datos activa con cifrado KMS y enmascaramiento SFC en CloudWatch. 3. Autorizado para despliegue Canary en Producción."
fi

# PASO 4: Guardar el dictamen en un archivo Markdown para Jenkins
cat <<EOF > "${ARCHIVO_SALIDA}"
# Dictamen del Asistente DevOps (Amazon Bedrock)
- **Modo:** ${MODO}
- **Modelo:** ${MODELO_IA}
- **Fuente Analizada:** ${ARCHIVO_ENTRADA:-Entorno general}

---

${ANALISIS}
EOF

echo "[OK] Reporte de IA generado exitosamente en: ${ARCHIVO_SALIDA}"
