#!/usr/bin/env bash
# ── Step 5: App VM ────────────────────────────────────────────────────────────
# Creates the App VM running FastAPI + nginx + certbot.
# After creation, point your domain's A record to the external IP printed below.
#
# Run once: bash provision/05_app_vm.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/config.sh"

gcloud config set project "${GCP_PROJECT}"

echo "==> Creating App VM: ${APP_VM} (${APP_VM_TYPE})"
gcloud compute instances create "${APP_VM}" \
  --zone="${GCP_ZONE}" \
  --machine-type="${APP_VM_TYPE}" \
  --image-family="ubuntu-2404-lts-amd64" \
  --image-project="ubuntu-os-cloud" \
  --service-account="${APP_SA}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --scopes="cloud-platform" \
  --tags="${APP_TAG}" \
  --boot-disk-size="20GB" \
  --boot-disk-type="pd-standard" \
  --project="${GCP_PROJECT}"

EXTERNAL_IP=$(gcloud compute instances describe "${APP_VM}" \
  --zone="${GCP_ZONE}" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)" \
  --project="${GCP_PROJECT}")

echo ""
echo "✅  App VM created."
echo "    External IP: ${EXTERNAL_IP}"
echo ""
echo "⚠️  NEXT STEPS:"
echo "   1. Point your domain's A record to: ${EXTERNAL_IP}"
echo "      (DuckDNS: https://www.duckdns.org  |  Namecheap: Dashboard → DNS)"
echo "   2. Wait ~5 min for DNS to propagate, then run:"
echo "      bash bootstrap/app_bootstrap.sh"
echo "   3. SSH into App VM:"
echo "      gcloud compute ssh ${APP_VM} --zone=${GCP_ZONE}"
