# marketlens-infra

Infrastructure-as-scripts for MarketLens. Manages GCP resource provisioning,
secret management via Google Secret Manager, and deployment automation.

## Architecture

```
[ Vercel ]                    [ GCP asia-south1 VPC ]
  marketlens-fe  ──HTTPS──▶  marketlens-app (e2-micro)
                               nginx + FastAPI + certbot
                               ──VPC private──▶  marketlens-db (e2-small)
                                                  TimescaleDB
                                                  Persistent SSD disk
                                                  ──weekly──▶ GCS bucket
[ Local Machine ]
  DBeaver ──SSH tunnel──▶ marketlens-db:5432
```

Secrets live in **GCP Secret Manager** — no `.env` files in git or manually copied to VMs.

---

## First-time setup order

```
1. Edit provision/config.sh   ← set your GCP project ID + zone
2. bash provision/01_iam.sh   ← create service accounts
3. bash provision/02_network.sh  ← firewall rules
4. bash provision/03_secrets.sh  ← create secret placeholders
   → Fill in all secrets in GCP Console → Secret Manager
5. bash provision/04_db_vm.sh    ← create DB VM + disk
   → Save the internal IP: echo -n "10.x.x.x" | gcloud secrets versions add marketlens-db-internal-ip --data-file=-
6. bash provision/06_gcs_bucket.sh  ← create backup bucket
   → Create HMAC keys → save as secrets
7. bash provision/05_app_vm.sh   ← create App VM
   → Point domain A record to the printed external IP
8. SSH into DB VM → run bootstrap/db_bootstrap.sh
9. SSH into App VM → run bootstrap/app_bootstrap.sh
```

---

## Deploying updates (after first setup)

```bash
# Deploy backend code change
bash deploy/deploy_be.sh

# Deploy without rebuilding Docker image (config/secret change only)
bash deploy/deploy_be.sh --no-build

# Deploy DB config change (rare)
bash deploy/deploy_db.sh
```

---

## Directory structure

```
provision/
  config.sh          ← shared config: project ID, zone, VM names
  01_iam.sh          ← service accounts + IAM roles
  02_network.sh      ← GCP firewall rules
  03_secrets.sh      ← create Secret Manager secret placeholders
  04_db_vm.sh        ← DB VM + 20GB persistent SSD disk
  05_app_vm.sh       ← App VM
  06_gcs_bucket.sh   ← GCS backup bucket + 90-day lifecycle

bootstrap/
  db_bootstrap.sh    ← run once on DB VM: Docker, mount disk, pull secrets, start DB
  app_bootstrap.sh   ← run once on App VM: Docker, pull secrets, SSL, start API

deploy/
  _secrets.sh        ← shared helper: pull secrets → write .env files
  deploy_db.sh       ← update DB VM: pull code + secrets, restart
  deploy_be.sh       ← update App VM: pull code + secrets, rebuild, restart

secrets/
  README.md          ← secret inventory (names + descriptions, NO values)
```

---

## Secret management

All secrets are stored in GCP Secret Manager. VMs pull them at deploy time
using their attached service account (no credentials needed on the VM).

See `secrets/README.md` for the full inventory and rotation procedures.

---

## Repositories

| Repo | Description |
|---|---|
| [marketlens-be](https://github.com/mudit4158/marketlens-be) | FastAPI backend |
| [marketlens-fe](https://github.com/mudit4158/marketlens-fe) | React frontend (deployed on Vercel) |
| [marketlens-infra](https://github.com/mudit4158/marketlens-infra) | This repo |
