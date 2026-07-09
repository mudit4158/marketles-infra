#!/usr/bin/env bash
# ── Step 2: Firewall rules ────────────────────────────────────────────────────
# Creates three rules:
#   allow-ssh          → :22 open to all (needed for deploys + SSH tunnel)
#   allow-http-https   → :80/:443 open to all (app VM only, via tag)
#   allow-postgres-vpc → :5432 open within VPC only (db VM only, via tag)
#
# Run once: bash provision/02_network.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
source "$(dirname "$0")/config.sh"

gcloud config set project "${GCP_PROJECT}"

echo "==> Creating firewall rule: allow-ssh"
gcloud compute firewall-rules create allow-ssh \
  --allow tcp:22 \
  --source-ranges 0.0.0.0/0 \
  --description "SSH from anywhere (deploy + local tunnel)" \
  --project="${GCP_PROJECT}" || echo "  (already exists, skipping)"

echo "==> Creating firewall rule: allow-http-https (tag: ${APP_TAG})"
gcloud compute firewall-rules create allow-http-https \
  --allow tcp:80,tcp:443 \
  --source-ranges 0.0.0.0/0 \
  --target-tags "${APP_TAG}" \
  --description "Public web traffic to app VM only" \
  --project="${GCP_PROJECT}" || echo "  (already exists, skipping)"

echo "==> Creating firewall rule: allow-postgres-vpc (tag: ${DB_TAG})"
gcloud compute firewall-rules create allow-postgres-vpc \
  --allow tcp:5432 \
  --source-ranges 10.128.0.0/9 \
  --target-tags "${DB_TAG}" \
  --description "Postgres reachable from VPC internal IPs only — never public" \
  --project="${GCP_PROJECT}" || echo "  (already exists, skipping)"

echo ""
echo "✅  Firewall rules created."
echo "    Port 5432 is NOT reachable from the internet."
echo "    Use SSH tunnel for local DB access: see secrets/README.md"
