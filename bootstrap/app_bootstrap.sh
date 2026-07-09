#!/usr/bin/env bash
# ── App VM bootstrap (run once after VM creation) ─────────────────────────────
# Run from your LOCAL machine (not from inside the VM):
#   gcloud compute ssh marketlens-app --zone=asia-south1-a -- 'bash -s' < bootstrap/app_bootstrap.sh
#
# What it does:
#   1. Installs Docker (uses sudo throughout — no group-change gymnastics)
#   2. Clones the marketlens-be repo
#   3. Pulls secrets from Secret Manager → writes .env.app
#   4. Updates nginx config with real domain
#   5. Starts nginx with HTTP-only bootstrap config → runs certbot → swaps to full config
#   6. Starts all services (nginx + FastAPI)
#   7. Runs alembic migrations + seed + backfill
#   8. Sets up certbot auto-renewal cron
#
# Prerequisites:
#   - Domain A record pointing to this VM's external IP BEFORE running
#   - DB VM bootstrap complete and TimescaleDB healthy
#   - marketlens-db-internal-ip secret set in Secret Manager
#   - All secrets set in Secret Manager (run provision/03_secrets.sh first)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BE_REPO="https://github.com/mudit4158/marketlens-be.git"
BE_DIR="/opt/marketlens"
ENV_FILE="${BE_DIR}/.env.app"

echo "==> [1/8] Installing Docker"
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
echo "    Docker installed."

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

echo "==> [4/8] Verifying nginx config has correct domain"
if grep -q "api.yourdomain.com" "${BE_DIR}/nginx/conf.d/marketlens.conf"; then
  echo "    WARNING: nginx config still has placeholder domain — fixing..."
  sed -i "s/api.yourdomain.com/${SSL_DOMAIN}/g" "${BE_DIR}/nginx/conf.d/marketlens.conf"
fi
echo "    nginx domain: $(grep server_name ${BE_DIR}/nginx/conf.d/marketlens.conf | head -1)"

echo "==> [5/8] Getting SSL certificate for ${SSL_DOMAIN}"
cd "${BE_DIR}"

# Phase 1: start nginx with HTTP-only bootstrap config (no SSL certs or api upstream needed)
# Disable the full config temporarily so nginx starts cleanly
mv "${BE_DIR}/nginx/conf.d/marketlens.conf" "${BE_DIR}/nginx/conf.d/marketlens.conf.disabled"
sudo docker compose -f docker-compose.app.yml up -d nginx

echo "    Waiting for nginx to be ready on port 80..."
for i in $(seq 1 10); do
  if curl -sf http://localhost:80/ > /dev/null 2>&1; then
    echo "    nginx is up."
    break
  fi
  sleep 3
done

# Phase 2: run certbot
sudo docker compose -f docker-compose.app.yml --env-file "${ENV_FILE}" run --rm certbot

# Phase 3: restore full config (SSL certs now exist) and remove bootstrap config
mv "${BE_DIR}/nginx/conf.d/marketlens.conf.disabled" "${BE_DIR}/nginx/conf.d/marketlens.conf"
rm -f "${BE_DIR}/nginx/conf.d/certbot-bootstrap.conf"

echo "==> [6/8] Starting all services (nginx + FastAPI)"
sudo docker compose -f docker-compose.app.yml --env-file "${ENV_FILE}" up -d

echo "    Waiting for API to be healthy..."
for i in $(seq 1 30); do
  if sudo docker exec marketlens-api curl -sf http://localhost:8001/health > /dev/null 2>&1; then
    echo "    API is healthy."
    break
  fi
  echo "    Attempt ${i}/30 — waiting..."
  sleep 5
done

echo "==> [7/8] Running migrations, seed, and backfill"
sudo docker exec marketlens-api python -m alembic upgrade head
sudo docker exec marketlens-api python -m scripts.seed_instruments
echo "    Running 1d backfill (this takes a few minutes)..."
sudo docker exec marketlens-api python -m scripts.backfill_prices --intervals 1d --symbols GOLD,USDINR
echo "    Running intraday backfill..."
sudo docker exec marketlens-api python -m scripts.backfill_prices --intervals 1h,5m --symbols GOLD,USDINR

echo "==> [8/8] Setting up certbot auto-renewal cron"
(crontab -l 2>/dev/null; echo "0 3 * * * cd ${BE_DIR} && sudo docker compose -f docker-compose.app.yml --env-file ${ENV_FILE} run --rm certbot && sudo docker compose -f docker-compose.app.yml exec nginx nginx -s reload") | crontab -

echo ""
echo "✅  App bootstrap complete."
echo "    API health: curl https://${SSL_DOMAIN}/health"
