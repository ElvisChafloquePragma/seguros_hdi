#!/usr/bin/env bash
set -e

# ==============================================================================
# Validación de Parámetros por Ambiente 
# Valida que dev.json, staging.json y prod.json cumplan las reglas de schema.json
# ==============================================================================

SCHEMA="infra/params/schema.json"

echo "[INFO] Validando archivos de parámetros contra ${SCHEMA}"

for archivo in infra/params/dev.json infra/params/staging.json infra/params/prod.json; do
  echo "  -> Revisando ${archivo} contra ${SCHEMA}"
  check-jsonschema --schemafile "${SCHEMA}" "${archivo}"
done

echo "[OK] Todos los parámetros (dev, staging, prod) cumplen con schema.json"
