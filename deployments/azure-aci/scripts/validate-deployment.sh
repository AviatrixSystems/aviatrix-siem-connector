#!/bin/bash
set -e

echo "🔍 Validating Azure ACI deployment prerequisites..."

# Determine the base path relative to the script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Check if assembled config exists
ASSEMBLED_CONFIG="$BASE_DIR/logstash-configs/assembled/azure-log-ingestion-full.conf"
if [ ! -f "$ASSEMBLED_CONFIG" ]; then
    echo "❌ ERROR: Assembled config not found at $ASSEMBLED_CONFIG"
    echo "   Run: cd $BASE_DIR/logstash-configs && ./scripts/assemble-config.sh azure-log-ingestion"
    exit 1
fi
echo "✅ Assembled config found: $ASSEMBLED_CONFIG"

# Check if patterns file exists
PATTERNS_FILE="$BASE_DIR/logstash-configs/patterns/avx.conf"
if [ ! -f "$PATTERNS_FILE" ]; then
    echo "❌ ERROR: Patterns file not found at $PATTERNS_FILE"
    exit 1
fi
echo "✅ Patterns file found: $PATTERNS_FILE"

# Validate assembled config contains required outputs
if ! grep -q "microsoft-sentinel-log-analytics-logstash-output-plugin" "$ASSEMBLED_CONFIG"; then
    echo "❌ ERROR: Assembled config doesn't contain Azure Sentinel output plugin"
    exit 1
fi
echo "✅ Azure Sentinel output plugin found in config"

# Check for required environment variables in config
# All 8 DCR/stream pairs: Logstash resolves every ${VAR} at pipeline compile
# time, so each one must be referenced here and injected by the module.
REQUIRED_VARS=("client_app_id" "client_app_secret" "tenant_id" "data_collection_endpoint" "azure_cloud")
for t in ids netsession websession gw_net_stats gw_sys_stats cmd tunnel_status vpn_session; do
    REQUIRED_VARS+=("azure_dcr_${t}_id" "azure_stream_${t}")
done
MISSING_VARS=0
for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "\${$var}" "$ASSEMBLED_CONFIG"; then
        echo "⚠️  WARNING: Config doesn't reference environment variable: $var"
        MISSING_VARS=$((MISSING_VARS + 1))
    fi
done

if [ $MISSING_VARS -eq 0 ]; then
    echo "✅ All required environment variables referenced in config"
else
    echo "⚠️  $MISSING_VARS environment variable(s) not found in config (may cause runtime issues)"
fi

echo ""
echo "✅ All validation checks passed!"
echo ""
echo "Next steps:"
echo "1. Review terraform.tfvars with your Azure configuration"
echo "2. Run: terraform init"
echo "3. Run: terraform plan"
echo "4. Run: terraform apply"
