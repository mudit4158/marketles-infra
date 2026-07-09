#!/usr/bin/env bash
# ── App VM bootstrap (run once after VM creation) ─────────────────────────────
# SSH into the App VM and run this script:
#   gcloud compute ssh marketlens-app --zone=asia-south1-a
#   bash <(curl -fsSL https://raw.githubusercontent.com/mudit4158/marketlens-infra/main/bootstrap/app_bootstrap.sh)
#
# What it does:
#   1. Installs Docker
#   2. Clones the marketlens-be repo
#   3. Pulls secrets from Secret Manager → writes .env.app
#   4. Updates nginx config with real domain
#   5. Obtains SSL certificate via certbot
#   6. Starts nginx + FastAPI
#   7. Runs alembic migrations + seed + backfill
#   8. Sets up certbot auto-renewal cron
#
# Prerequisites:
#   - Domain A record already pointing to this VM's external IP
#   - All secrets set in Secret Manager (run provision/03_secrets.sh first)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BE_REPO="https://github.com/mudit4158/marketlens-be.git"
BE_DIR="/opt/marketlens"
ENV_FILE="${BE_DIR}/.env.app"

echo "==> [1/8] Installing Docker"
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
newgrp docker <<'DOCKERGRP'

BE_REPO="https://github.com/mudit4158/marketlens-be.git"
BE_DIR="/opt/marketlens"
ENV_FILE="${BE_DIR}/.env.app"

echo "==> [2/8] Cloning marketlens-be"
sudo git clone "${BE_REPO}" "${BE_DIR}" 2>/dev/null || (cd "${BE_DIR}" && sudo git pull origin main)
sudo chown -R "$USER":"$USER" "${BE_DIR}"

echo "==> [3/8] Pulling secrets from Secret Manager → ${ENV_FILE}"
pull_secret() {
  gcloud secrets versions access latest --secret="$1" 2>/dev/null || echo ""
}

DB_PASSWORD=$(pull_secret "marketlens-db-password")
DB_INTERNAL_IP=$(pull_secret "marketlens-db-internal-ip")
API_KEY=$(pull_secret "marketlens-api-key")
CORS_ORIGINS=$(pull_secret "marketlens-cors-origins")
SSL_DOMAIN=$(pull_secret "marketlens-ssl-domain")
SSL_EMAIL=$(pull_secret "marketlens-ssl-email")

cat > "${ENV_FILE}" <<EOF
ENVIRONMENT=production
LOG_LEVEL=INFO

DATABASE_URL=postgresql+psycopg2://marketlens:${DB_PASSWORD}@${DB_INTERNAL_IP}:5432/marketlens

CORS_ALLOWED_ORIGINS=${CORS_ORIGINS}
CORS_ALLOWED_ORIGIN_REGEX=

API_KEY=${API_KEY}

SCHEDULER_ENABLED=true
SCHEDULER_CRON_HOUR=22
SCHEDULER_CRON_MINUTE=0
SCHEDULER_CRON_DAY_OF_WEEK=mon-fri
SCHEDULER_INGESTION_INTERVALS=1d,1h,5m
SCHEDULER_SOURCE_NAME=yfinance

DOMAIN=${SSL_DOMAIN}
SSL_EMAIL=${SSL_EMAIL}
EOF

chmod 600 "${ENV_FILE}"
echo "    .env.app written (permissions: 600)"

echo "==> [4/8] Updating nginx config with domain: ${SSL_DOMAIN}"
sed -i "s/api.yourdomain.com/${SSL_DOMAIN}/g" "${BE_DIR}/nginx/conf.d/marketlens.conf"

echo "==> [5/8] Starting nginx with HTTP-only bootstrap config for certbot challenge"
cd "${BE_DIR}"
# Temporarily rename the full config so nginx starts without needing the SSL cert or api upstream
mv "${BE_DIR}/nginx/conf.d/marketlens.conf" "${BE_DIR}/nginx/conf.d/marketlens.conf.disabled"
docker compose -f docker-compose.app.yml up -d nginx
sleep 5

echo "==> [6/8] Obtaining SSL certificate for ${SSL_DOMAIN}"
docker compose -f docker-compose.app.yml --env-file "${ENV_FILE}" run --rm certbot

# Restore the full config now that certs exist
mv "${BE_DIR}/nginx/conf.d/marketlens.conf.disabled" "${BE_DIR}/nginx/conf.d/marketlens.conf"
# Remove the bootstrap config so only the full config is active
rm -f "${BE_DIR}/nginx/conf.d/certbot-bootstrap.conf"

echo "==> [7/8] Starting all services (nginx + FastAPI)"
docker compose -f docker-compose.app.yml --env-file "${ENV_FILE}" up -d

echo "    Waiting for API to be healthy..."
sleep 20
docker exec marketlens-api python -m alembic upgrade head
docker exec marketlens-api python -m scripts.seed_instruments
echo "    Running 1d backfill (this takes a few minutes)..."
docker exec marketlens-api python -m scripts.backfill_prices --intervals 1d --symbols GOLD,USDINR
echo "    Running intraday backfill..."
docker exec marketlens-api python -m scripts.backfill_prices --intervals 1h,5m --symbols GOLD,USDINR

echo "==> [8/8] Setting up certbot auto-renewal cron"
(crontab -l 2>/dev/null; echo "0 3 * * * cd ${BE_DIR} && docker compose -f docker-compose.app.yml --env-file ${ENV_FILE} run --rm certbot && docker compose -f docker-compose.app.yml exec nginx nginx -s reload") | crontab -

echo ""
echo "✅  App bootstrap complete."
echo "    API health: curl https://${SSL_DOMAIN}/health"
DOCKERGRP
