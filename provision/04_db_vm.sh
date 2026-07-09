#!/usr/bin/env bash
# ── Step 4: DB VM + Persistent Disk ──────────────────────────────────────────
# Creates:
#   - 20GB SSD persistent disk (auto-delete=no — survives VM deletion)
#   - DB VM attached to that disk, running as the DB service account
#
# After this runs:
#   1. Get the DB VM's internal IP:
#      gcloud compute instances describe marketlens-db --zone=asia-south1-a \
#        --format="get(networkInterfaces[0].networkIP)"
#   2. Save that IP as the secret:
#      echo -n "10.128.x.x" | gcloud secrets versions add marketlens-db-internal-ip --data-file=-
#
# Run once: bash provision/04_db_vm.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/config.sh"

gcloud config set project "${GCP_PROJECT}"

echo "==> Creating persistent SSD disk: ${DB_DISK} (${DB_DISK_SIZE})"
gcloud compute disks create "${DB_DISK}" \
  --size="${DB_DISK_SIZE}" \
  --type="${DB_DISK_TYPE}" \
  --zone="${GCP_ZONE}" \
  --project="${GCP_PROJECT}" || echo "  (already exists, skipping)"

echo "==> Creating DB VM: ${DB_VM} (${DB_VM_TYPE})"
gcloud compute instances create "${DB_VM}" \
  --zone="${GCP_ZONE}" \
  --machine-type="${DB_VM_TYPE}" \
  --image-family="ubuntu-2404-lts-amd64" \
  --image-project="ubuntu-os-cloud" \
  --service-account="${DB_SA}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --scopes="cloud-platform" \
  --disk="name=${DB_DISK},auto-delete=no,boot=no" \
  --tags="${DB_TAG}" \
  --boot-disk-size="20GB" \
  --boot-disk-type="pd-standard" \
  --project="${GCP_PROJECT}"

echo ""
echo "✅  DB VM created."
echo ""
echo "==> Fetching internal IP..."
INTERNAL_IP=$(gcloud compute instances describe "${DB_VM}" \
  --zone="${GCP_ZONE}" \
  --format="get(networkInterfaces[0].networkIP)" \
  --project="${GCP_PROJECT}")

EXTERNAL_IP=$(gcloud compute instances describe "${DB_VM}" \
  --zone="${GCP_ZONE}" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)" \
  --project="${GCP_PROJECT}")

echo "    Internal IP: ${INTERNAL_IP}  (use this in DATABASE_URL)"
echo "    External IP: ${EXTERNAL_IP}  (use this for SSH tunnel)"
echo ""
echo "⚠️  Save the internal IP as a secret now:"
echo "   echo -n '${INTERNAL_IP}' | gcloud secrets versions add marketlens-db-internal-ip --data-file=-"
echo ""
echo "Next: run bootstrap/db_bootstrap.sh on the DB VM"
echo "   gcloud compute ssh ${DB_VM} --zone=${GCP_ZONE}"
