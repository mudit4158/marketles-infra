#!/usr/bin/env bash
# ── Shared secret helper ──────────────────────────────────────────────────────
# Sourced by deploy_db.sh and deploy_be.sh.
# Pulls all secrets from Google Secret Manager and writes .env files.
# Requires: gcloud CLI authenticated + Secret Manager access via service account.
# ─────────────────────────────────────────────────────────────────────────────

pull_secret() {
  local name="$1"
  local value
  value=$(gcloud secrets versions access latest --secret="${name}" 2>/dev/null)
  if [ -z "${value}" ]; then
    echo "⚠️  WARNING: secret '${name}' is empty or not found" >&2
  fi
  echo "${value}"
}

write_db_env() {
  local env_file="$1"
  echo "  Pulling DB secrets from Secret Manager..."

  DB_PASSWORD=$(pull_secret "marketlens-db-password")
  GCS_ACCESS=$(pull_secret "marketlens-backup-gcs-access")
  GCS_SECRET=$(pull_secret "marketlens-backup-gcs-secret")
  GCS_BUCKET=$(pull_secret "marketlens-backup-gcs-bucket")

  cat > "${env_file}" <<EOF
POSTGRES_USER=marketlens
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=marketlens
BACKUP_S3_ACCESS_KEY=${GCS_ACCESS}
BACKUP_S3_SECRET_KEY=${GCS_SECRET}
BACKUP_S3_REGION=auto
BACKUP_S3_BUCKET=${GCS_BUCKET}
EOF
  chmod 600 "${env_file}"
  echo "  .env.db written ✓"
}

write_app_env() {
  local env_file="$1"
  echo "  Pulling App secrets from Secret Manager..."

  DB_PASSWORD=$(pull_secret "marketlens-db-password")
  DB_INTERNAL_IP=$(pull_secret "marketlens-db-internal-ip")
  API_KEY=$(pull_secret "marketlens-api-key")
  CORS_ORIGINS=$(pull_secret "marketlens-cors-origins")
  SSL_DOMAIN=$(pull_secret "marketlens-ssl-domain")
  SSL_EMAIL=$(pull_secret "marketlens-ssl-email")
  UPSTOX_API_KEY=$(pull_secret "marketlens-upstox-api-key")
  UPSTOX_API_SECRET=$(pull_secret "marketlens-upstox-api-secret")
  cat > "${env_file}" <<EOF
ENVIRONMENT=production
LOG_LEVEL=INFO
DATABASE_URL=postgresql+psycopg2://marketlens:${DB_PASSWORD}@${DB_INTERNAL_IP}:5432/marketlens
CORS_ALLOWED_ORIGINS=${CORS_ORIGINS}
CORS_ALLOWED_ORIGIN_REGEX=
API_KEY=${API_KEY}
SCHEDULER_ENABLED=true
SCHEDULER_INGESTION_INTERVALS=1d,1h,5m,1m
SCHEDULER_SOURCE_NAME=yfinance
DOMAIN=${SSL_DOMAIN}
SSL_EMAIL=${SSL_EMAIL}
UPSTOX_API_KEY=${UPSTOX_API_KEY}
UPSTOX_API_SECRET=${UPSTOX_API_SECRET}
EOF
  chmod 600 "${env_file}"
  echo "  .env.app written ✓"
}
