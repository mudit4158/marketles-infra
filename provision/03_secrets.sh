#!/usr/bin/env bash
# ── Step 3: Create Secret Manager secrets ────────────────────────────────────
# Creates all secret *placeholders* in Google Secret Manager with empty values.
# After running this, go to GCP Console → Secret Manager and set real values.
#
# Secrets created:
#   marketlens-db-password          Postgres password (shared by DB + App VMs)
#   marketlens-db-internal-ip       DB VM's VPC internal IP (set after VM is created)
#   marketlens-api-key              X-API-Key shared between Vercel FE and FastAPI
#   marketlens-backup-gcs-access    GCS HMAC access key for pg_dump uploads
#   marketlens-backup-gcs-secret    GCS HMAC secret key for pg_dump uploads
#   marketlens-backup-gcs-bucket    GCS bucket name for backups
#   marketlens-ssl-domain           API domain (e.g. api.yourdomain.com)
#   marketlens-ssl-email            Email for Let's Encrypt cert
#   marketlens-cors-origins         Allowed CORS origins (Vercel URL)
#
# Run once: bash provision/03_secrets.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/config.sh"

gcloud config set project "${GCP_PROJECT}"

# Enable Secret Manager API
gcloud services enable secretmanager.googleapis.com --project="${GCP_PROJECT}"

SECRETS=(
  "marketlens-db-password:Postgres password — strong random string"
  "marketlens-db-internal-ip:DB VM internal VPC IP — set after VM is created (Step 4)"
  "marketlens-api-key:X-API-Key header secret — shared between Vercel FE and FastAPI"
  "marketlens-backup-gcs-access:GCS HMAC access key for weekly pg_dump backup"
  "marketlens-backup-gcs-secret:GCS HMAC secret key for weekly pg_dump backup"
  "marketlens-backup-gcs-bucket:GCS bucket name e.g. marketlens-backups"
  "marketlens-ssl-domain:API domain e.g. api.yourdomain.com or marketlens.duckdns.org"
  "marketlens-ssl-email:Email for Let's Encrypt certificate renewal notices"
  "marketlens-cors-origins:Comma-separated allowed CORS origins e.g. https://marketlens-fe.vercel.app"
  "marketlens-upstox-api-key:Upstox API key from the Upstox developer portal"
  "marketlens-upstox-api-secret:Upstox API secret from the Upstox developer portal"
  "marketlens-upstox-mobile:Upstox registered mobile number (10 digits, no +91)"
  "marketlens-upstox-pin:Upstox 6-digit login PIN"
  "marketlens-upstox-totp-secret:Base32 TOTP secret from Upstox 2FA setup page"
)

for entry in "${SECRETS[@]}"; do
  name="${entry%%:*}"
  desc="${entry#*:}"

  existing=$(gcloud secrets describe "${name}" --project="${GCP_PROJECT}" 2>/dev/null || true)
  if [ -n "${existing}" ]; then
    echo "  ⏭  ${name} already exists, skipping"
    continue
  fi

  echo "==> Creating secret: ${name}"
  echo -n "PLACEHOLDER" | gcloud secrets create "${name}" \
    --data-file=- \
    --replication-policy="automatic" \
    --labels="app=marketlens" \
    --project="${GCP_PROJECT}"
done

echo ""
echo "✅  All secrets created."
echo ""
echo "⚠️  NEXT STEP: Set real values in GCP Console → Secret Manager"
echo "   Or use gcloud to set each value:"
echo "   echo -n 'YOUR_VALUE' | gcloud secrets versions add marketlens-db-password --data-file=-"
echo ""
echo "   Secrets to fill in:"
for entry in "${SECRETS[@]}"; do
  name="${entry%%:*}"
  desc="${entry#*:}"
  echo "     ${name}"
  echo "       → ${desc}"
done
