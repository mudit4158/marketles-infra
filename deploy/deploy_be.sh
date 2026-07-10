#!/usr/bin/env bash
# ── Deploy App VM ─────────────────────────────────────────────────────────────
# Run from your LOCAL machine.
# SSHes into the App VM, refreshes secrets, rebuilds the API image, restarts.
#
# Usage:
#   bash deploy/deploy_be.sh              # full deploy (rebuild image)
#   bash deploy/deploy_be.sh --no-build  # restart only (skip image rebuild)
#
# Note: image is currently built on the VM from source (git pull + docker build).
# Future improvement: push pre-built image from CI → GCP Artifact Registry,
# and have this script do docker pull instead of build.
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
UPSTOX_API_KEY=\$(pull_secret "marketlens-upstox-api-key")
UPSTOX_API_SECRET=\$(pull_secret "marketlens-upstox-api-secret")
UPSTOX_MOBILE=\$(pull_secret "marketlens-upstox-mobile")
UPSTOX_PIN=\$(pull_secret "marketlens-upstox-pin")
UPSTOX_TOTP_SECRET=\$(pull_secret "marketlens-upstox-totp-secret")
cat > "\${ENV_FILE}" <<EOF
ENVIRONMENT=production
LOG_LEVEL=INFO
DATABASE_URL=postgresql+psycopg2://marketlens:\${DB_PASSWORD}@\${DB_INTERNAL_IP}:5432/marketlens
CORS_ALLOWED_ORIGINS=\${CORS_ORIGINS}
CORS_ALLOWED_ORIGIN_REGEX=
API_KEY=\${API_KEY}
SCHEDULER_ENABLED=true
SCHEDULER_INGESTION_INTERVALS=1d,1h,5m,1m
SCHEDULER_SOURCE_NAME=yfinance
DOMAIN=\${SSL_DOMAIN}
SSL_EMAIL=\${SSL_EMAIL}
UPSTOX_API_KEY=\${UPSTOX_API_KEY}
UPSTOX_API_SECRET=\${UPSTOX_API_SECRET}
UPSTOX_MOBILE=\${UPSTOX_MOBILE}
UPSTOX_PIN=\${UPSTOX_PIN}
UPSTOX_TOTP_SECRET=\${UPSTOX_TOTP_SECRET}
EOF
chmod 600 "\${ENV_FILE}"

echo "  Restarting services..."
cd "\${BE_DIR}"
sudo docker compose -f docker-compose.app.yml --env-file "\${ENV_FILE}" up -d ${BUILD_FLAG}

echo "  Waiting for API to be healthy..."
for i in \$(seq 1 30); do
  if sudo docker exec marketlens-api curl -sf http://localhost:8001/health > /dev/null 2>&1; then
    echo "  API is healthy ✓"
    break
  fi
  echo "  Attempt \${i}/30 — waiting..."
  sleep 5
done

echo "  Running any pending migrations..."
sudo docker exec marketlens-api python -m alembic upgrade head

echo "✅  App deploy complete."
REMOTE
