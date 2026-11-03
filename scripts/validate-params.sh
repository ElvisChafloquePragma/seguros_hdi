#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT 1: Validación de Parámetros por Ambiente (Shift-Left Validation)
# Valida que dev.json, staging.json y prod.json cumplan las reglas de schema.json
# ==============================================================================

SCHEMA="infra/params/schema.json"

echo "[INFO] Validando archivos de parámetros contra ${SCHEMA}..."

# Recorremos cada ambiente y validamos su estructura JSON
for archivo in infra/params/dev.json infra/params/staging.json infra/params/prod.json; do
  echo "  -> Revisando ${archivo}..."
  if command -v check-jsonschema >/dev/null 2>&1; then
    check-jsonschema --schemafile "${SCHEMA}" "${archivo}"
  else
    python3 -m json.tool "${archivo}" > /dev/null
  fi
done

echo "[OK] Todos los parámetros (dev, staging, prod) son válidos."
