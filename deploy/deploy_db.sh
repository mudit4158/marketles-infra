#!/usr/bin/env bash
# ── Deploy DB VM ──────────────────────────────────────────────────────────────
# Run from your LOCAL machine.
# SSHes into the DB VM, refreshes secrets, and restarts TimescaleDB if needed.
#
# Usage: bash deploy/deploy_db.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/../provision/config.sh"

echo "==> Deploying DB VM: ${DB_VM}"

gcloud compute ssh "${DB_VM}" --zone="${GCP_ZONE}" --project="${GCP_PROJECT}" -- bash -s <<'REMOTE'
set -euo pipefail
BE_DIR="/opt/marketlens"
ENV_FILE="${BE_DIR}/.env.db"

pull_secret() {
  gcloud secrets versions access latest --secret="$1" 2>/dev/null || echo ""
}

echo "  Pulling latest code..."
cd "${BE_DIR}" && git pull origin main

echo "  Refreshing secrets from Secret Manager..."
DB_PASSWORD=$(pull_secret "marketlens-db-password")
GCS_ACCESS=$(pull_secret "marketlens-backup-gcs-access")
GCS_SECRET=$(pull_secret "marketlens-backup-gcs-secret")
GCS_BUCKET=$(pull_secret "marketlens-backup-gcs-bucket")

cat > "${ENV_FILE}" <<EOF
POSTGRES_USER=marketlens
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=marketlens
BACKUP_S3_ACCESS_KEY=${GCS_ACCESS}
BACKUP_S3_SECRET_KEY=${GCS_SECRET}
BACKUP_S3_REGION=auto
BACKUP_S3_BUCKET=${GCS_BUCKET}
EOF
chmod 600 "${ENV_FILE}"

echo "  Restarting services..."
cd "${BE_DIR}"
docker compose -f docker-compose.db.yml --env-file "${ENV_FILE}" up -d

echo "  Verifying DB health..."
sleep 5
docker exec marketlens-timescaledb pg_isready -U marketlens -d marketlens

echo "✅  DB deploy complete."
REMOTE
