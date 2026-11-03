#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT 1: Validación de Parámetros por Ambiente (Shift-Left Validation)
# Valida que dev.json, staging.json y prod.json cumplan las reglas de schema.json
# ==============================================================================

SCHEMA="infra/params/schema.json"

echo "[INFO] Validando archivos de parámetros contra ${SCHEMA}..."

# Recorremos cada ambiente y validamos su estructura JSON contra schema.json
for archivo in infra/params/dev.json infra/params/staging.json infra/params/prod.json; do
  echo "  -> Revisando ${archivo} contra ${SCHEMA}..."
  check-jsonschema --schemafile "${SCHEMA}" "${archivo}"
done

echo "[OK] Todos los parámetros (dev, staging, prod) cumplen con schema.json."
