#!/usr/bin/env bash
# ── Deploy App VM ─────────────────────────────────────────────────────────────
# Run from your LOCAL machine.
# SSHes into the App VM, refreshes secrets, rebuilds the API image, restarts.
#
# Usage:
#   bash deploy/deploy_be.sh              # full deploy (rebuild image)
#   bash deploy/deploy_be.sh --no-build  # restart only (skip image rebuild)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/../provision/config.sh"

BUILD_FLAG="--build api"
if [[ "${1:-}" == "--no-build" ]]; then
  BUILD_FLAG=""
  echo "==> Skipping image rebuild (--no-build)"
fi

echo "==> Deploying App VM: ${APP_VM}"

gcloud compute ssh "${APP_VM}" --zone="${GCP_ZONE}" --project="${GCP_PROJECT}" -- bash -s <<REMOTE
set -euo pipefail
BE_DIR="/opt/marketlens"
ENV_FILE="\${BE_DIR}/.env.app"

pull_secret() {
  gcloud secrets versions access latest --secret="\$1" 2>/dev/null || echo ""
}

echo "  Pulling latest code..."
cd "\${BE_DIR}" && git pull origin main

echo "  Refreshing secrets from Secret Manager..."
DB_PASSWORD=\$(pull_secret "marketlens-db-password")
DB_INTERNAL_IP=\$(pull_secret "marketlens-db-internal-ip")
API_KEY=\$(pull_secret "marketlens-api-key")
CORS_ORIGINS=\$(pull_secret "marketlens-cors-origins")
SSL_DOMAIN=\$(pull_secret "marketlens-ssl-domain")
SSL_EMAIL=\$(pull_secret "marketlens-ssl-email")

cat > "\${ENV_FILE}" <<EOF
ENVIRONMENT=production
LOG_LEVEL=INFO
DATABASE_URL=postgresql+psycopg2://marketlens:\${DB_PASSWORD}@\${DB_INTERNAL_IP}:5432/marketlens
CORS_ALLOWED_ORIGINS=\${CORS_ORIGINS}
CORS_ALLOWED_ORIGIN_REGEX=
API_KEY=\${API_KEY}
SCHEDULER_ENABLED=true
SCHEDULER_CRON_HOUR=22
SCHEDULER_CRON_MINUTE=0
SCHEDULER_CRON_DAY_OF_WEEK=mon-fri
SCHEDULER_INGESTION_INTERVALS=1d,1h,5m
SCHEDULER_SOURCE_NAME=yfinance
DOMAIN=\${SSL_DOMAIN}
SSL_EMAIL=\${SSL_EMAIL}
EOF
chmod 600 "\${ENV_FILE}"

echo "  Restarting services (${BUILD_FLAG:-no rebuild})..."
cd "\${BE_DIR}"
docker compose -f docker-compose.app.yml --env-file "\${ENV_FILE}" up -d ${BUILD_FLAG}

echo "  Running any pending migrations..."
sleep 10
docker exec marketlens-api python -m alembic upgrade head

echo "  Verifying API health..."
curl -sf http://localhost:8001/health | grep -q "ok" && echo "  API is healthy ✓"

echo "✅  App deploy complete."
REMOTE
