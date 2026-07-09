#!/usr/bin/env bash
# ── DB VM bootstrap (run once after VM creation) ──────────────────────────────
# SSH into the DB VM and run this script:
#   gcloud compute ssh marketlens-db --zone=asia-south1-a
#   bash <(curl -fsSL https://raw.githubusercontent.com/mudit4158/marketlens-infra/main/bootstrap/db_bootstrap.sh)
#
# What it does:
#   1. Installs Docker
#   2. Formats and mounts the persistent disk at /mnt/disks/pgdata
#   3. Clones the marketlens-be repo
#   4. Pulls secrets from Secret Manager → writes .env.db
#   5. Starts TimescaleDB
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BE_REPO="https://github.com/mudit4158/marketlens-be.git"
BE_DIR="/opt/marketlens"
MOUNT_POINT="/mnt/disks/pgdata"
ENV_FILE="${BE_DIR}/.env.db"

echo "==> [1/5] Installing Docker"
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"

echo "==> [2/5] Mounting persistent disk"
# Find the attached data disk (not the boot disk, which is /dev/sda)
DATA_DISK=$(lsblk -dpno NAME,TYPE | awk '$2=="disk"' | grep -v sda | awk '{print $1}' | head -1)
echo "    Detected data disk: ${DATA_DISK}"

# Format only if not already formatted
if ! sudo blkid "${DATA_DISK}" | grep -q ext4; then
  echo "    Formatting ${DATA_DISK} as ext4..."
  sudo mkfs.ext4 -F "${DATA_DISK}"
fi

sudo mkdir -p "${MOUNT_POINT}"
sudo mount "${DATA_DISK}" "${MOUNT_POINT}" 2>/dev/null || true

# Persist mount across reboots
UUID=$(sudo blkid -s UUID -o value "${DATA_DISK}")
if ! grep -q "${UUID}" /etc/fstab; then
  echo "UUID=${UUID} ${MOUNT_POINT} ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
fi
sudo chmod 777 "${MOUNT_POINT}"
echo "    Mounted at ${MOUNT_POINT}"

echo "==> [3/5] Cloning marketlens-be"
sudo git clone "${BE_REPO}" "${BE_DIR}" 2>/dev/null || (cd "${BE_DIR}" && sudo git pull origin main)
sudo chown -R "$USER":"$USER" "${BE_DIR}"

echo "==> [4/5] Pulling secrets from Secret Manager → ${ENV_FILE}"
pull_secret() {
  gcloud secrets versions access latest --secret="$1" 2>/dev/null || echo ""
}

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
echo "    .env.db written (permissions: 600)"

echo "==> [5/5] Starting TimescaleDB"
cd "${BE_DIR}"
docker compose -f docker-compose.db.yml --env-file "${ENV_FILE}" up -d

echo ""
echo "✅  DB bootstrap complete."
echo "    Verify: docker exec marketlens-timescaledb pg_isready -U marketlens -d marketlens"
