#!/usr/bin/env bash
# ── Step 6: GCS backup bucket ─────────────────────────────────────────────────
# Creates the GCS bucket for weekly pg_dump backups.
# Also enables HMAC key interoperability so the backup sidecar can use
# S3-compatible credentials to upload.
#
# Run once: bash provision/06_gcs_bucket.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/config.sh"

gcloud config set project "${GCP_PROJECT}"

echo "==> Creating GCS bucket: gs://${BACKUP_BUCKET}"
gcloud storage buckets create "gs://${BACKUP_BUCKET}" \
  --location="${GCP_REGION}" \
  --uniform-bucket-level-access \
  --project="${GCP_PROJECT}" || echo "  (already exists, skipping)"

# Set a lifecycle rule: delete objects older than 90 days (keep ~13 weekly backups)
cat > /tmp/lifecycle.json <<'EOF'
{
  "lifecycle": {
    "rule": [{
      "action": { "type": "Delete" },
      "condition": { "age": 90 }
    }]
  }
}
EOF
gcloud storage buckets update "gs://${BACKUP_BUCKET}" \
  --lifecycle-file=/tmp/lifecycle.json

echo ""
echo "✅  GCS bucket created: gs://${BACKUP_BUCKET}"
echo "    Lifecycle: objects auto-deleted after 90 days (~13 weekly backups retained)"
echo ""
echo "⚠️  Create HMAC keys for S3-compatible backup access:"
echo "   GCP Console → Cloud Storage → Settings → Interoperability"
echo "   → Create a key for service account: ${DB_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"
echo ""
echo "   Then save the keys as secrets:"
echo "   echo -n 'GOOG...' | gcloud secrets versions add marketlens-backup-gcs-access --data-file=-"
echo "   echo -n 'your-secret' | gcloud secrets versions add marketlens-backup-gcs-secret --data-file=-"
echo "   echo -n '${BACKUP_BUCKET}' | gcloud secrets versions add marketlens-backup-gcs-bucket --data-file=-"
