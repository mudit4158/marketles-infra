#!/usr/bin/env bash
# ── Step 1: Service accounts + IAM roles ──────────────────────────────────────
# Creates two service accounts:
#   marketlens-db-sa  → Secret Manager read access (for DB VM)
#   marketlens-app-sa → Secret Manager read access (for App VM)
#
# Run once: bash provision/01_iam.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "==> Setting project to ${GCP_PROJECT}"
gcloud config set project "${GCP_PROJECT}"

# ── DB service account ────────────────────────────────────────────────────────
echo "==> Creating service account: ${DB_SA}"
gcloud iam service-accounts create "${DB_SA}" \
  --display-name="MarketLens DB VM" \
  --project="${GCP_PROJECT}" || echo "  (already exists, skipping)"

gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${DB_SA}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${DB_SA}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"   # for GCS backup writes

# ── App service account ───────────────────────────────────────────────────────
echo "==> Creating service account: ${APP_SA}"
gcloud iam service-accounts create "${APP_SA}" \
  --display-name="MarketLens App VM" \
  --project="${GCP_PROJECT}" || echo "  (already exists, skipping)"

gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${APP_SA}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

echo ""
echo "✅  IAM setup complete."
echo "    DB SA:  ${DB_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"
echo "    App SA: ${APP_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"
