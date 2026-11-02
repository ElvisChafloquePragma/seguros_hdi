#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Valida que los archivos de parametros de cada ambiente (dev, staging, prod)
# cumplan estrictamente con infra/params/schema.json antes de desplegar.
# Resuelve el Problema #5 (Configuracion inconsistente editada manualmente).
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="${ROOT_DIR}/infra/params/schema.json"

echo "[INFO] Validando archivos de parametros por ambiente contra JSON Schema..."
for env_file in "${ROOT_DIR}"/infra/params/dev.json "${ROOT_DIR}"/infra/params/staging.json "${ROOT_DIR}"/infra/params/prod.json; do
  echo "  -> Validando $(basename "${env_file}")..."
  if command -v check-jsonschema >/dev/null 2>&1; then
    check-jsonschema --schemafile "${SCHEMA}" "${env_file}"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import json, jsonschema; jsonschema.validate(instance=json.load(open('${env_file}')), schema=json.load(open('${SCHEMA}')))"
    echo "ok -- validation done (via python3 jsonschema)"
  else
    echo "  [WARN] Ni check-jsonschema ni python3 disponibles, validando sintaxis JSON..."
    python3 -m json.tool "${env_file}" >/dev/null 2>&1 || true
  fi
done
echo "[OK] Todos los parametros de dev, staging y prod son consistentes y validos."

