#!/usr/bin/env bash
# ── Shared config ─────────────────────────────────────────────────────────────
# All provision and deploy scripts source this file.
# Edit these values once before running any script.
# ─────────────────────────────────────────────────────────────────────────────

export GCP_PROJECT="marketlens-501914"
export SSL_DOMAIN="marketlenss.duckdns.org"     # DuckDNS subdomain
export GCP_REGION="asia-south1"                  # Mumbai
export GCP_ZONE="asia-south1-a"

# VM names
export DB_VM="marketlens-db"
export APP_VM="marketlens-app"

# Disk
export DB_DISK="marketlens-db-disk"
export DB_DISK_SIZE="20GB"
export DB_DISK_TYPE="pd-ssd"
export DB_DISK_MOUNT="/mnt/disks/pgdata"

# Machine types
export DB_VM_TYPE="e2-small"    # 2GB RAM — minimum for TimescaleDB
export APP_VM_TYPE="e2-micro"   # 1GB RAM — enough for FastAPI + nginx

# Service accounts
export DB_SA="marketlens-db-sa"
export APP_SA="marketlens-app-sa"

# Network tags (used by firewall rules)
export DB_TAG="marketlens-db"
export APP_TAG="marketlens-app"

# GCS bucket for DB backups
export BACKUP_BUCKET="marketlens-backups-${GCP_PROJECT}"

# GitHub repo to clone on VMs
export BE_REPO="https://github.com/mudit4158/marketlens-be.git"
export BE_DIR="/opt/marketlens"
