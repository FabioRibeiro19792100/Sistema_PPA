#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Uso: $0 <supabase_url> <anon_key> <environment>"
  exit 1
fi

SUPABASE_URL="$1"
ANON_KEY="$2"
ENVIRONMENT="$3"

delete_table() {
  local table="$1"
  curl -fsS -X DELETE \
    "${SUPABASE_URL}/rest/v1/${table}?environment=eq.${ENVIRONMENT}" \
    -H "apikey: ${ANON_KEY}" \
    -H "Authorization: Bearer ${ANON_KEY}" \
    -H "Prefer: return=minimal"
}

echo "Resetando ambiente '${ENVIRONMENT}'..."

# Dependências primeiro
delete_table "eventos_auditoria"
delete_table "backups_log"
delete_table "avaliacao_criterios"
delete_table "avaliacoes"
delete_table "atribuicoes"
delete_table "distribuicoes"
delete_table "participantes"
delete_table "inscricoes"
delete_table "import_rows_raw"
delete_table "imports"
delete_table "pareceristas"
delete_table "configuracoes_sistema"

echo "Reset concluído para '${ENVIRONMENT}'."
