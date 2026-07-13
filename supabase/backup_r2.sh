#!/usr/bin/env bash
# Backup automático do banco Supabase do PPA → Cloudflare R2 (bucket-mastertech/backup-ppa/)
# Credenciais via variáveis de ambiente — nunca hardcoded aqui.
set -euo pipefail

# ── Configuração ────────────────────────────────────────────────────────────
R2_ACCOUNT_ID="${R2_ACCOUNT_ID:-ae16e49b7837faeee19e2ccb4bb717f8}"
R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:?Defina R2_ACCESS_KEY_ID}"
R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:?Defina R2_SECRET_ACCESS_KEY}"
R2_BUCKET="bucket-mastertech"
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
R2_PREFIX="backup-ppa"
DATABASE_URL="${DATABASE_URL:?Defina DATABASE_URL com a connection string do Supabase}"
RETENTION_DAYS=30
# ────────────────────────────────────────────────────────────────────────────

# Verifica dependências
for cmd in pg_dump gzip aws; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Dependência ausente: $cmd" >&2
    exit 1
  fi
done

DATE_TAG="$(date +%Y-%m-%d_%H-%M-%S)"
FILENAME="ppa_backup_${DATE_TAG}.sql.gz"
TMP_FILE="/tmp/${FILENAME}"

echo "📦 Gerando dump do banco..."
pg_dump "${DATABASE_URL}" \
  --no-owner \
  --no-acl \
  --format=plain \
  | gzip -9 > "${TMP_FILE}"

SIZE=$(du -sh "${TMP_FILE}" | cut -f1)
echo "✅ Dump gerado: ${FILENAME} (${SIZE})"

echo "☁️  Enviando para R2..."
AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
aws s3 cp "${TMP_FILE}" \
  "s3://${R2_BUCKET}/${R2_PREFIX}/${FILENAME}" \
  --endpoint-url "${R2_ENDPOINT}" \
  --region auto

echo "✅ Backup enviado: ${R2_PREFIX}/${FILENAME}"

rm -f "${TMP_FILE}"

# Limpa backups mais antigos que RETENTION_DAYS
echo "🧹 Removendo backups com mais de ${RETENTION_DAYS} dias..."
CUTOFF=$(date -d "-${RETENTION_DAYS} days" +%Y-%m-%d 2>/dev/null || date -v -${RETENTION_DAYS}d +%Y-%m-%d)

AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
aws s3 ls "s3://${R2_BUCKET}/${R2_PREFIX}/" \
  --endpoint-url "${R2_ENDPOINT}" \
  --region auto \
  | awk '{print $4}' \
  | while read -r key; do
      FILE_DATE=$(echo "$key" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
      if [[ -n "$FILE_DATE" && "$FILE_DATE" < "$CUTOFF" ]]; then
        echo "  🗑  Removendo: ${key}"
        AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
        AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
        aws s3 rm "s3://${R2_BUCKET}/${R2_PREFIX}/${key}" \
          --endpoint-url "${R2_ENDPOINT}" \
          --region auto
      fi
    done

echo "✅ Backup concluído com sucesso."
