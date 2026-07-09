# MarketLens — Secret Inventory

All secrets live in **GCP Secret Manager** under project `your-gcp-project-id`.
**Never store actual values here.** This file documents what each secret is, who uses it, and how to rotate it.

Access secrets in GCP Console → Secret Manager, or via:
```bash
gcloud secrets versions access latest --secret=<name>
```

---

## Secret Registry

| Secret Name | Used By | Description | How to Rotate |
|---|---|---|---|
| `marketlens-db-password` | DB VM + App VM | Postgres password for user `marketlens` | 1. Generate new password  2. Update secret  3. Run `deploy_db.sh` + `deploy_be.sh` |
| `marketlens-db-internal-ip` | App VM | VPC internal IP of DB VM (e.g. `10.128.0.2`) | Only changes if DB VM is recreated — run `04_db_vm.sh` output |
| `marketlens-api-key` | App VM + Vercel | `X-API-Key` shared secret between FE and BE | 1. Generate new key  2. Update secret  3. Update Vercel env var  4. `deploy_be.sh` |
| `marketlens-backup-gcs-access` | DB VM | GCS HMAC access key for weekly pg_dump | Rotate in GCP Console → Cloud Storage → Settings → Interoperability |
| `marketlens-backup-gcs-secret` | DB VM | GCS HMAC secret key for weekly pg_dump | Same as above |
| `marketlens-backup-gcs-bucket` | DB VM | GCS bucket name e.g. `marketlens-backups-<project>` | Static — only changes if bucket is renamed |
| `marketlens-ssl-domain` | App VM | API domain e.g. `api.marketlens.duckdns.org` | Update DNS + secret + re-run certbot |
| `marketlens-ssl-email` | App VM | Email for Let's Encrypt renewal notices | Low-sensitivity — update anytime |
| `marketlens-cors-origins` | App VM | Allowed CORS origins e.g. `https://marketlens-fe.vercel.app` | Update when Vercel domain changes |

---

## Setting a secret value

```bash
# First time (after 03_secrets.sh created the placeholder):
echo -n "your-actual-value" | gcloud secrets versions add marketlens-db-password --data-file=-

# Updating an existing secret (creates a new version, old versions retained):
echo -n "new-value" | gcloud secrets versions add marketlens-db-password --data-file=-
```

---

## Vercel environment variables (set in Vercel dashboard)

These are NOT in Secret Manager — they live in Vercel project settings:

| Variable | Value |
|---|---|
| `VITE_API_BASE` | `https://<your-ssl-domain>` e.g. `https://api.marketlens.duckdns.org` |
| `VITE_API_KEY` | Same value as `marketlens-api-key` secret |

Set at: Vercel Dashboard → marketlens-fe → Settings → Environment Variables

---

## Generating strong secrets

```bash
# Strong random password (32 chars)
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Or with openssl
openssl rand -base64 32
```

---

## Local DBeaver access (SSH tunnel)

Port 5432 is never exposed to the internet. Use an SSH tunnel:

```bash
# Keep this running while using DBeaver
gcloud compute ssh marketlens-db --zone=asia-south1-a -- -L 5433:localhost:5432 -N

# DBeaver connection:
# Host:     localhost
# Port:     5433
# Database: marketlens
# Username: marketlens
# Password: (value of marketlens-db-password secret)
```
