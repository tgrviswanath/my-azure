#!/bin/bash
# deploy_website.sh — Deploy static website to Azure Storage + purge CDN
#
# Usage: bash code/deploy_website.sh
# Prerequisites: az login, terraform apply completed

set -euo pipefail

# Read values from Terraform outputs
RESOURCE_GROUP="static-website-rg"
STORAGE_ACCOUNT=$(az storage account list \
  --resource-group $RESOURCE_GROUP \
  --query "[0].name" -o tsv)
CDN_PROFILE="static-site-cdn-profile"
CDN_ENDPOINT="${STORAGE_ACCOUNT}-endpoint"

echo "============================================"
echo "  Azure Static Website Deployment"
echo "============================================"
echo "[*] Storage Account: $STORAGE_ACCOUNT"
echo "[*] CDN Endpoint:    $CDN_ENDPOINT"

# Step 1: Upload all website files to $web container
echo ""
echo "[1/3] Uploading website files..."
az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT" \
  --source "$(dirname "$0")/website/" \
  --destination '$web' \
  --overwrite true \
  --output table

# Step 2: Set cache headers on HTML files (short cache)
echo ""
echo "[2/3] Setting cache headers..."
az storage blob update \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name '$web' \
  --name "index.html" \
  --content-cache-control "public, max-age=300" 2>/dev/null || true

# Step 3: Purge CDN cache
echo ""
echo "[3/3] Purging CDN cache..."
az cdn endpoint purge \
  --name "$CDN_ENDPOINT" \
  --profile-name "$CDN_PROFILE" \
  --resource-group "$RESOURCE_GROUP" \
  --content-paths "/*"

# Get URLs
STORAGE_URL=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "primaryEndpoints.web" -o tsv)

CDN_URL="https://${CDN_ENDPOINT}.azureedge.net"

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo ""
echo "  Storage URL: $STORAGE_URL"
echo "  CDN URL:     $CDN_URL"
echo ""
echo "  Note: CDN cache purge takes 2-5 minutes"
echo "============================================"
