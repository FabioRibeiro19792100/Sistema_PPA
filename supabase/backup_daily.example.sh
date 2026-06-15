#!/usr/bin/env bash
set -euo pipefail

# Exemplo de backup diário externo.
# Ajuste as variáveis antes de usar.

ENVIRONMENT="${1:-homolog}"
DATE_TAG="$(date +%Y-%m-%d)"
BACKUP_DIR="${BACKUP_DIR:-./backups/${ENVIRONMENT}}"
mkdir -p "${BACKUP_DIR}"

case "${ENVIRONMENT}" in
  homolog)
    DATABASE_URL="${SUPABASE_DB_URL_HOMOLOG:-}"
    ;;
  producao)
    DATABASE_URL="${SUPABASE_DB_URL_PRODUCAO:-}"
    ;;
  *)
    echo "Ambiente inválido: ${ENVIRONMENT}" >&2
    exit 1
    ;;
esac

if [[ -z "${DATABASE_URL}" ]]; then
  echo "DATABASE_URL ausente para ${ENVIRONMENT}" >&2
  exit 1
fi

OUT_FILE="${BACKUP_DIR}/ppa_${ENVIRONMENT}_${DATE_TAG}.dump"

pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --dbname="${DATABASE_URL}" \
  --file="${OUT_FILE}"

echo "Backup gerado em ${OUT_FILE}"
