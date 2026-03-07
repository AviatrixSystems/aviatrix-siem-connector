#!/usr/bin/env bash
# Aviatrix SIEM Connector — AWS Quickstart
#
# Deploy an Aviatrix syslog-to-SIEM connector on ECS Fargate in one command.
#
# Usage:
#   wget -qO- https://github.com/AviatrixSystems/aviatrix-siem-connector/releases/latest/download/quickstart-aws.sh | bash -s -- \
#     --output-type splunk-hec \
#     --vpc-id vpc-xxx \
#     --subnets subnet-aaa,subnet-bbb \
#     --splunk-address 10.0.0.5 \
#     --splunk-hec-token xxx

set -euo pipefail

# --- Defaults ---
OUTPUT_TYPE=""
VPC_ID=""
SUBNETS=""
INTERNAL_NLB="false"
SYSLOG_PORT="5000"
LOG_PROFILE="all"
IMAGE_TAG="latest"
STACK_NAME="avx-siem-connector"
REGION=""
DESTROY=false
PLAN_ONLY=false
TERRAFORM_VERSION="1.9.8"
GITHUB_REPO="AviatrixSystems/aviatrix-siem-connector"

# SIEM-specific vars (collected into logstash_config_variables map)
declare -A CONFIG_VARS

# --- Parse args ---
print_usage() {
  cat <<'USAGE'
Aviatrix SIEM Connector — AWS Quickstart

Required:
  --output-type <type>          splunk-hec, dynatrace, dynatrace-metrics,
                                dynatrace-logs, zabbix, azure-log-ingestion
  --vpc-id <vpc-id>             VPC for NLB and ECS tasks
  --subnets <id,id,...>         Comma-separated subnet IDs (multi-AZ recommended)

Optional:
  --internal                    Create internal NLB (default: internet-facing)
  --syslog-port <port>          Syslog listen port (default: 5000)
  --log-profile <profile>       all, security, or networking (default: all)
  --image-tag <tag>             Container image tag (default: latest)
  --name <name>                 Stack name / working directory (default: avx-siem-connector)
  --region <region>             AWS region (default: current CLI region)

SIEM-specific (pass credentials for your chosen output type):
  --splunk-address <addr>       Splunk HEC server address
  --splunk-port <port>          Splunk HEC port (default: 8088)
  --splunk-hec-token <token>    Splunk HEC authentication token
  --dt-metrics-url <url>        Dynatrace metrics ingest URL
  --dt-logs-url <url>           Dynatrace logs ingest URL
  --dt-api-token <token>        Dynatrace API token
  --dt-logs-token <token>       Dynatrace logs token (if different from API token)
  --zabbix-server <addr>        Zabbix server address
  --zabbix-port <port>          Zabbix trapper port (default: 10051)

Lifecycle:
  --destroy                     Tear down an existing deployment
  --plan                        Show what would be created (don't apply)
  -h, --help                    Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-type)      OUTPUT_TYPE="$2"; shift 2 ;;
    --vpc-id)           VPC_ID="$2"; shift 2 ;;
    --subnets)          SUBNETS="$2"; shift 2 ;;
    --internal)         INTERNAL_NLB="true"; shift ;;
    --syslog-port)      SYSLOG_PORT="$2"; shift 2 ;;
    --log-profile)      LOG_PROFILE="$2"; shift 2 ;;
    --image-tag)        IMAGE_TAG="$2"; shift 2 ;;
    --name)             STACK_NAME="$2"; shift 2 ;;
    --region)           REGION="$2"; shift 2 ;;
    --destroy)          DESTROY=true; shift ;;
    --plan)             PLAN_ONLY=true; shift ;;
    # Splunk
    --splunk-address)   CONFIG_VARS[SPLUNK_ADDRESS]="$2"; shift 2 ;;
    --splunk-port)      CONFIG_VARS[SPLUNK_PORT]="$2"; shift 2 ;;
    --splunk-hec-token) CONFIG_VARS[SPLUNK_HEC_AUTH]="$2"; shift 2 ;;
    # Dynatrace
    --dt-metrics-url)   CONFIG_VARS[DT_METRICS_URL]="$2"; shift 2 ;;
    --dt-logs-url)      CONFIG_VARS[DT_LOGS_URL]="$2"; shift 2 ;;
    --dt-api-token)     CONFIG_VARS[DT_API_TOKEN]="$2"; shift 2 ;;
    --dt-logs-token)    CONFIG_VARS[DT_LOGS_TOKEN]="$2"; shift 2 ;;
    # Zabbix
    --zabbix-server)    CONFIG_VARS[ZABBIX_SERVER]="$2"; shift 2 ;;
    --zabbix-port)      CONFIG_VARS[ZABBIX_PORT]="$2"; shift 2 ;;
    -h|--help)          print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

# --- Handle destroy ---
if $DESTROY; then
  WORK_DIR="$HOME/$STACK_NAME"
  if [[ ! -d "$WORK_DIR" ]]; then
    echo "Error: Deployment directory not found: $WORK_DIR"
    echo "Make sure --name matches the name used during deployment."
    exit 1
  fi
  echo "Destroying deployment in $WORK_DIR..."
  cd "$WORK_DIR"
  terraform destroy -auto-approve
  echo ""
  echo "Deployment destroyed. You can remove the directory: rm -rf $WORK_DIR"
  exit 0
fi

# --- Validate required args ---
MISSING=()
[[ -z "$OUTPUT_TYPE" ]] && MISSING+=("--output-type")
[[ -z "$VPC_ID" ]]      && MISSING+=("--vpc-id")
[[ -z "$SUBNETS" ]]     && MISSING+=("--subnets")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Error: Missing required arguments: ${MISSING[*]}"
  echo ""
  print_usage
  exit 1
fi

# --- Validate SIEM-specific args ---
case "$OUTPUT_TYPE" in
  splunk-hec)
    [[ -z "${CONFIG_VARS[SPLUNK_ADDRESS]:-}" ]] && { echo "Error: --splunk-address is required for splunk-hec"; exit 1; }
    [[ -z "${CONFIG_VARS[SPLUNK_HEC_AUTH]:-}" ]] && { echo "Error: --splunk-hec-token is required for splunk-hec"; exit 1; }
    ;;
  dynatrace)
    [[ -z "${CONFIG_VARS[DT_METRICS_URL]:-}" ]] && { echo "Error: --dt-metrics-url is required for dynatrace"; exit 1; }
    [[ -z "${CONFIG_VARS[DT_LOGS_URL]:-}" ]]    && { echo "Error: --dt-logs-url is required for dynatrace"; exit 1; }
    [[ -z "${CONFIG_VARS[DT_API_TOKEN]:-}" ]]   && { echo "Error: --dt-api-token is required for dynatrace"; exit 1; }
    # Default DT_LOGS_TOKEN to DT_API_TOKEN if not set
    [[ -z "${CONFIG_VARS[DT_LOGS_TOKEN]:-}" ]]  && CONFIG_VARS[DT_LOGS_TOKEN]="${CONFIG_VARS[DT_API_TOKEN]}"
    ;;
  dynatrace-metrics)
    [[ -z "${CONFIG_VARS[DT_METRICS_URL]:-}" ]] && { echo "Error: --dt-metrics-url is required for dynatrace-metrics"; exit 1; }
    [[ -z "${CONFIG_VARS[DT_API_TOKEN]:-}" ]]   && { echo "Error: --dt-api-token is required for dynatrace-metrics"; exit 1; }
    ;;
  dynatrace-logs)
    [[ -z "${CONFIG_VARS[DT_LOGS_URL]:-}" ]]   && { echo "Error: --dt-logs-url is required for dynatrace-logs"; exit 1; }
    [[ -z "${CONFIG_VARS[DT_API_TOKEN]:-}" ]]   && { echo "Error: --dt-api-token is required for dynatrace-logs"; exit 1; }
    # Default DT_LOGS_TOKEN to DT_API_TOKEN if not set
    [[ -z "${CONFIG_VARS[DT_LOGS_TOKEN]:-}" ]]  && CONFIG_VARS[DT_LOGS_TOKEN]="${CONFIG_VARS[DT_API_TOKEN]}"
    ;;
  zabbix)
    [[ -z "${CONFIG_VARS[ZABBIX_SERVER]:-}" ]] && { echo "Error: --zabbix-server is required for zabbix"; exit 1; }
    ;;
esac

echo "============================================"
echo " Aviatrix SIEM Connector — AWS Quickstart"
echo "============================================"
echo ""
echo "  Output type:  $OUTPUT_TYPE"
echo "  VPC:          $VPC_ID"
echo "  Subnets:      $SUBNETS"
echo "  Internal NLB: $INTERNAL_NLB"
echo "  Syslog port:  $SYSLOG_PORT"
echo "  Image tag:    $IMAGE_TAG"
echo ""

# --- Install Terraform if needed ---
if ! command -v terraform &>/dev/null; then
  echo "Terraform not found. Installing v${TERRAFORM_VERSION}..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) TF_ARCH="amd64" ;;
    aarch64|arm64) TF_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
  esac
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  TF_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${TF_ARCH}.zip"
  TF_TMP="$(mktemp -d)"
  curl -sL "$TF_URL" -o "$TF_TMP/terraform.zip"
  unzip -qo "$TF_TMP/terraform.zip" -d "$TF_TMP"
  mkdir -p "$HOME/.local/bin"
  mv "$TF_TMP/terraform" "$HOME/.local/bin/terraform"
  rm -rf "$TF_TMP"
  export PATH="$HOME/.local/bin:$PATH"
  echo "Terraform installed: $(terraform version -json | head -1)"
fi

# --- Download Terraform module ---
WORK_DIR="$HOME/$STACK_NAME"
mkdir -p "$WORK_DIR"

# Determine release URL
if [[ "$IMAGE_TAG" == "latest" ]]; then
  RELEASE_URL="https://github.com/$GITHUB_REPO/releases/latest/download"
else
  RELEASE_URL="https://github.com/$GITHUB_REPO/releases/download/${IMAGE_TAG}"
fi

# Only download if not already present (idempotent)
if [[ ! -f "$WORK_DIR/main.tf" ]]; then
  echo "Downloading Terraform module..."
  curl -sL "$RELEASE_URL/quickstart-aws.tar.gz" -o "$WORK_DIR/quickstart-aws.tar.gz"
  tar -xzf "$WORK_DIR/quickstart-aws.tar.gz" -C "$WORK_DIR" --strip-components=1
  rm "$WORK_DIR/quickstart-aws.tar.gz"
fi

# --- Generate terraform.tfvars ---
cd "$WORK_DIR"

# Convert comma-separated subnets to HCL list
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNETS"
SUBNET_HCL=$(printf ', "%s"' "${SUBNET_ARRAY[@]}")
SUBNET_HCL="[${SUBNET_HCL:2}]"

# Build logstash_config_variables map
CONFIG_MAP="{"
for key in "${!CONFIG_VARS[@]}"; do
  CONFIG_MAP+=$'\n'"    $key = \"${CONFIG_VARS[$key]}\""
done
CONFIG_MAP+=$'\n'"  }"

cat > terraform.tfvars <<EOF
vpc_id          = "$VPC_ID"
subnet_ids      = $SUBNET_HCL
output_type     = "$OUTPUT_TYPE"
internal_nlb = $INTERNAL_NLB
syslog_port     = $SYSLOG_PORT
log_profile     = "$LOG_PROFILE"
image_tag       = "$IMAGE_TAG"
logstash_config_variables = $CONFIG_MAP
EOF

# Add region if specified
if [[ -n "$REGION" ]]; then
  echo "aws_region = \"$REGION\"" >> terraform.tfvars
fi

echo "Terraform config written to $WORK_DIR/terraform.tfvars"

# --- Run Terraform ---
if [[ ! -d ".terraform" ]]; then
  echo "Initializing Terraform..."
  terraform init -input=false
fi

if $PLAN_ONLY; then
  echo ""
  echo "Running terraform plan..."
  terraform plan
  echo ""
  echo "To apply: re-run without --plan"
  exit 0
fi

echo ""
echo "Deploying..."
terraform apply -auto-approve

echo ""
echo "============================================"
echo " Deployment Complete!"
echo "============================================"
echo ""
SYSLOG_EP=$(terraform output -raw syslog_endpoint 2>/dev/null || echo "see terraform output")
LOG_GROUP=$(terraform output -raw cloudwatch_log_group 2>/dev/null || echo "see terraform output")
echo "  Syslog endpoint:  $SYSLOG_EP"
echo "  CloudWatch logs:  $LOG_GROUP"
echo ""
echo "Next steps:"
echo "  1. Configure your Aviatrix Controller to send syslog to: $SYSLOG_EP"
echo "  2. View logs: aws logs tail $LOG_GROUP --follow"
echo "  3. To destroy: re-run with --destroy --name $STACK_NAME"
echo ""
