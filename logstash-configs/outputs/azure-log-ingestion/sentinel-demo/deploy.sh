#!/usr/bin/env bash
# Deploy the Aviatrix -> Sentinel demo (workbook + analytics rules) into an existing
# Log Analytics workspace. Onboards Microsoft Sentinel if it isn't already enabled.
#
# Usage:
#   WS_RG=aviatrix-siem-connector WS_NAME=aviatrix-siem-workspace \
#   SUB=a9b9847f-ac2a-4fe8-95c7-727057b7e2e4 ./deploy.sh
set -euo pipefail

RG="${WS_RG:-aviatrix-siem-connector}"
WS="${WS_NAME:-aviatrix-siem-workspace}"
SUBSCRIPTION="${SUB:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -n "$SUBSCRIPTION" ] && az account set --subscription "$SUBSCRIPTION"

WS_RESOURCE_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$WS" --query id -o tsv)"

echo "==> Onboarding Microsoft Sentinel (idempotent)…"
az rest --method put \
  --url "https://management.azure.com${WS_RESOURCE_ID}/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2023-02-01" \
  --body '{"properties":{}}' >/dev/null

echo "==> Building workbook parameters…"
python3 - "$HERE" "$WS_RESOURCE_ID" <<'PY'
import json, sys
here, ws_id = sys.argv[1], sys.argv[2]
wb = open(f"{here}/workbook.json").read()
params = {
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workspaceResourceId": {"value": ws_id},
    "serializedData": {"value": wb}
  }
}
json.dump(params, open(f"{here}/arm/params.workbook.json", "w"))
PY

echo "==> Deploying workbook…"
az deployment group create -g "$RG" --name aviatrix-sentinel-workbook \
  --template-file "$HERE/arm/deploy-workbook.json" \
  --parameters @"$HERE/arm/params.workbook.json" \
  --query "properties.provisioningState" -o tsv

echo "==> Deploying IDS high-severity analytics rule…"
az deployment group create -g "$RG" --name aviatrix-ids-rule \
  --template-file "$HERE/analytics-rules/ids-high-severity.json" \
  --parameters workspaceName="$WS" --query "properties.provisioningState" -o tsv

echo "==> Deploying DCF egress-deny analytics rule…"
az deployment group create -g "$RG" --name aviatrix-dcf-egress-rule \
  --template-file "$HERE/analytics-rules/dcf-egress-deny.json" \
  --parameters workspaceName="$WS" --query "properties.provisioningState" -o tsv

echo "==> Done. Open Sentinel -> Workbooks -> 'Aviatrix Security (Sentinel Demo)'."
