#!/usr/bin/env bash
# =============================================================================
# Cloud Wave — Scratch Org Setup Script
# Usage: bash scripts/setup-cwdev.sh [scratch-org-alias] [duration-days]
#
# Required environment variables (export locally or set in CI):
#   SFDX_JWT_KEY_FILE        Path to server.key (JWT private key PEM file)
#   SFDX_CONSUMER_KEY_CWDEV  Connected App consumer key for DevHub
#   SFDX_USERNAME_CWDEV      DevHub username
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRATCH_ALIAS="${1:-cwDev}"
DURATION_DAYS="${2:-30}"
DEV_HUB_ALIAS="cwDevHub"
SCRATCH_DEF="config/project-scratch-def.json"
DATA_PLAN="data/sample-data-plan.json"

# Add your permission set API names here, e.g.:
#   PERMISSION_SETS=("CloudWave_Base_Access" "CloudWave_Admin")
PERMISSION_SETS=()

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
echo "::group::Preflight Validation"

for var in SFDX_JWT_KEY_FILE SFDX_CONSUMER_KEY_CWDEV SFDX_USERNAME_CWDEV; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable '$var' is not set." >&2
    exit 1
  fi
done

if [[ ! -f "$SFDX_JWT_KEY_FILE" ]]; then
  echo "ERROR: JWT key file not found at: $SFDX_JWT_KEY_FILE" >&2
  exit 1
fi

if [[ ! -f "$SCRATCH_DEF" ]]; then
  echo "ERROR: Scratch org definition not found at: $SCRATCH_DEF" >&2
  exit 1
fi

echo "Deployment Mode : SCRATCH ORG SETUP"
echo "Scratch Alias   : $SCRATCH_ALIAS"
echo "Duration (days) : $DURATION_DAYS"
echo "DevHub User     : $SFDX_USERNAME_CWDEV"
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 1: Authenticate DevHub via JWT Bearer Flow
# ---------------------------------------------------------------------------
echo "::group::Step 1 — DevHub Authentication"
echo "==> Authenticating DevHub ($SFDX_USERNAME_CWDEV) via JWT..."

sf org login jwt \
  --username       "$SFDX_USERNAME_CWDEV" \
  --jwt-key-file   "$SFDX_JWT_KEY_FILE" \
  --client-id      "$SFDX_CONSUMER_KEY_CWDEV" \
  --alias          "$DEV_HUB_ALIAS" \
  --set-default-dev-hub \
  --no-prompt

echo "==> DevHub authenticated successfully."
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 2: Create Scratch Org
# ---------------------------------------------------------------------------
echo "::group::Step 2 — Scratch Org Creation"
echo "==> Creating scratch org '$SCRATCH_ALIAS' (duration: ${DURATION_DAYS} days)..."

sf org create scratch \
  --definition-file "$SCRATCH_DEF" \
  --alias           "$SCRATCH_ALIAS" \
  --set-default \
  --duration-days   "$DURATION_DAYS" \
  --no-prompt

SCRATCH_ORG_USERNAME=$(sf org display --target-org "$SCRATCH_ALIAS" --json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['username'])")

echo "==> Scratch org created: $SCRATCH_ORG_USERNAME"
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 3: Push Source
# ---------------------------------------------------------------------------
echo "::group::Step 3 — Source Push"
echo "==> Pushing source to scratch org..."

sf project deploy start \
  --target-org     "$SCRATCH_ALIAS" \
  --ignore-conflicts \
  --wait 30

echo "==> Source push complete."
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 4: Import Sample Data
# ---------------------------------------------------------------------------
echo "::group::Step 4 — Sample Data Import"
if [[ -f "$DATA_PLAN" ]]; then
  echo "==> Importing sample data from $DATA_PLAN..."
  sf data import tree \
    --plan       "$DATA_PLAN" \
    --target-org "$SCRATCH_ALIAS"
  echo "==> Sample data import complete."
else
  echo "WARN: Data plan not found at $DATA_PLAN — skipping data import."
fi
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 5: Assign Permission Sets
# ---------------------------------------------------------------------------
echo "::group::Step 5 — Permission Set Assignment"
if [[ ${#PERMISSION_SETS[@]} -gt 0 ]]; then
  echo "==> Assigning permission sets..."
  for PS in "${PERMISSION_SETS[@]}"; do
    echo "    Assigning: $PS"
    sf org assign permset \
      --name       "$PS" \
      --target-org "$SCRATCH_ALIAS"
  done
  echo "==> Permission set assignment complete."
else
  echo "INFO: No permission sets configured — skipping."
  echo "      Add permission set API names to the PERMISSION_SETS array in this script."
fi
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 6: Open scratch org (interactive sessions only)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  echo "==> Opening scratch org in browser..."
  sf org open --target-org "$SCRATCH_ALIAS"
fi

echo ""
echo "============================================================"
echo " Cloud Wave Scratch Org Ready"
echo " Alias   : $SCRATCH_ALIAS"
echo " Username: $SCRATCH_ORG_USERNAME"
echo "============================================================"
