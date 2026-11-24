#!/usr/bin/env bash
# Aviatrix SIEM Connector — AWS Quickstart
#
# Deploy an Aviatrix syslog-to-SIEM connector on ECS Fargate in one command.
#
# Usage (the release asset is named quickstart.sh; curl -f fails loudly on 404):
#   curl -fsSL https://github.com/AviatrixSystems/aviatrix-siem-connector/releases/latest/download/quickstart.sh | bash -s -- \
#     --output-type splunk-hec \
#     --vpc-id vpc-xxx \
#     --subnets subnet-aaa,subnet-bbb \
#     --splunk-address 10.0.0.5 \
#     --splunk-hec-token xxx

set -euo pipefail

# Terraform auto-installed by a previous run lives here; keep it on PATH so a
# later --destroy (in a fresh shell) can find it.
export PATH="$HOME/.local/bin:$PATH"

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

ALLOWED_CIDRS=""

# SIEM-specific vars (collected into logstash_config_variables map).
# Stored as CV_<KEY> variables plus a key list instead of an associative
# array, so the script also runs on macOS's stock bash 3.2.
CONFIG_KEYS=""
set_cfg() {
  printf -v "CV_$1" '%s' "$2"
  case " $CONFIG_KEYS " in
    *" $1 "*) ;;
    *) CONFIG_KEYS="${CONFIG_KEYS:+$CONFIG_KEYS }$1" ;;
  esac
}
get_cfg() {
  local name="CV_$1"
  printf '%s' "${!name:-}"
}

# --- Parse args ---
print_usage() {
  cat <<'USAGE'
Aviatrix SIEM Connector — AWS Quickstart

Required:
  --output-type <type>          splunk-hec, dynatrace, dynatrace-metrics,
                                dynatrace-logs, zabbix
                                (azure-log-ingestion: use deployments/azure-aci)
  --vpc-id <vpc-id>             VPC for NLB and ECS tasks
  --subnets <id,id,...>         Comma-separated subnet IDs (multi-AZ recommended)

Optional:
  --internal                    Create internal NLB (default: internet-facing)
  --allowed-cidrs <cidr,...>    Source CIDRs allowed to send syslog
                                (default: 0.0.0.0/0; use your gateway egress IPs)
  --syslog-port <port>          Syslog listen port (default: 5000)
  --log-profile <profile>       all, security, or networking (default: all)
  --image-tag <tag>             Release/image tag (default: latest release,
                                resolved to its version tag)
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
    --allowed-cidrs)    ALLOWED_CIDRS="$2"; shift 2 ;;
    --syslog-port)      SYSLOG_PORT="$2"; shift 2 ;;
    --log-profile)      LOG_PROFILE="$2"; shift 2 ;;
    --image-tag)        IMAGE_TAG="$2"; shift 2 ;;
    --name)             STACK_NAME="$2"; shift 2 ;;
    --region)           REGION="$2"; shift 2 ;;
    --destroy)          DESTROY=true; shift ;;
    --plan)             PLAN_ONLY=true; shift ;;
    # Splunk
    --splunk-address)   set_cfg SPLUNK_ADDRESS "$2"; shift 2 ;;
    --splunk-port)      set_cfg SPLUNK_PORT "$2"; shift 2 ;;
    --splunk-hec-token) set_cfg SPLUNK_HEC_AUTH "$2"; shift 2 ;;
    # Dynatrace
    --dt-metrics-url)   set_cfg DT_METRICS_URL "$2"; shift 2 ;;
    --dt-logs-url)      set_cfg DT_LOGS_URL "$2"; shift 2 ;;
    --dt-api-token)     set_cfg DT_API_TOKEN "$2"; shift 2 ;;
    --dt-logs-token)    set_cfg DT_LOGS_TOKEN "$2"; shift 2 ;;
    # Zabbix
    --zabbix-server)    set_cfg ZABBIX_SERVER "$2"; shift 2 ;;
    --zabbix-port)      set_cfg ZABBIX_PORT "$2"; shift 2 ;;
    -h|--help)          print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

# --- Install Terraform if needed ---
sha256_of() {
  if command -v sha256sum &>/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

ensure_terraform() {
  command -v terraform &>/dev/null && return 0
  echo "Terraform not found. Installing v${TERRAFORM_VERSION} to $HOME/.local/bin..."
  local arch tf_arch os zip base tf_tmp expected actual
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) tf_arch="amd64" ;;
    aarch64|arm64) tf_arch="arm64" ;;
    *) echo "Unsupported architecture: $arch"; exit 1 ;;
  esac
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  zip="terraform_${TERRAFORM_VERSION}_${os}_${tf_arch}.zip"
  base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"
  tf_tmp="$(mktemp -d)"
  curl -fsSL "$base/$zip" -o "$tf_tmp/$zip"
  curl -fsSL "$base/terraform_${TERRAFORM_VERSION}_SHA256SUMS" -o "$tf_tmp/SHA256SUMS"
  expected=$(awk -v f="$zip" '$2 == f {print $1}' "$tf_tmp/SHA256SUMS")
  actual=$(sha256_of "$tf_tmp/$zip")
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    echo "Error: Terraform download checksum mismatch for $zip"
    rm -rf "$tf_tmp"
    exit 1
  fi
  unzip -qo "$tf_tmp/$zip" -d "$tf_tmp"
  mkdir -p "$HOME/.local/bin"
  mv "$tf_tmp/terraform" "$HOME/.local/bin/terraform"
  rm -rf "$tf_tmp"
  echo "Terraform installed: $(terraform version | head -1)"
}

# --- Handle destroy ---
if $DESTROY; then
  WORK_DIR="$HOME/$STACK_NAME"
  if [[ ! -d "$WORK_DIR" ]]; then
    echo "Error: Deployment directory not found: $WORK_DIR"
    echo "Make sure --name matches the name used during deployment."
    exit 1
  fi
  echo "Destroying deployment in $WORK_DIR..."
  ensure_terraform
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
need() {  # need <KEY> <flag>
  if [[ -z "$(get_cfg "$1")" ]]; then
    echo "Error: $2 is required for $OUTPUT_TYPE"
    exit 1
  fi
}
case "$OUTPUT_TYPE" in
  splunk-hec)
    need SPLUNK_ADDRESS --splunk-address
    need SPLUNK_HEC_AUTH --splunk-hec-token
    ;;
  dynatrace)
    need DT_METRICS_URL --dt-metrics-url
    need DT_LOGS_URL --dt-logs-url
    need DT_API_TOKEN --dt-api-token
    # Default DT_LOGS_TOKEN to DT_API_TOKEN if not set
    [[ -z "$(get_cfg DT_LOGS_TOKEN)" ]] && set_cfg DT_LOGS_TOKEN "$(get_cfg DT_API_TOKEN)"
    ;;
  dynatrace-metrics)
    need DT_METRICS_URL --dt-metrics-url
    need DT_API_TOKEN --dt-api-token
    ;;
  dynatrace-logs)
    need DT_LOGS_URL --dt-logs-url
    need DT_API_TOKEN --dt-api-token
    # Default DT_LOGS_TOKEN to DT_API_TOKEN if not set
    [[ -z "$(get_cfg DT_LOGS_TOKEN)" ]] && set_cfg DT_LOGS_TOKEN "$(get_cfg DT_API_TOKEN)"
    ;;
  zabbix)
    need ZABBIX_SERVER --zabbix-server
    ;;
  azure-log-ingestion)
    echo "Error: azure-log-ingestion needs Azure DCR/stream settings this quickstart has no flags for."
    echo "Use deployments/azure-aci (or deployments/aws-ecs-fargate with a tfvars file) instead."
    exit 1
    ;;
  *)
    echo "Error: unknown --output-type: $OUTPUT_TYPE"
    print_usage
    exit 1
    ;;
esac

# --- Resolve "latest" to a concrete release tag ---
# A mutable :latest image tag never changes the ECS task definition, so a
# re-run would not roll out a new release. Pin the version instead.
if [[ "$IMAGE_TAG" == "latest" ]]; then
  LATEST_URL=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$GITHUB_REPO/releases/latest" || true)
  if [[ "$LATEST_URL" == */tag/* ]]; then
    IMAGE_TAG="${LATEST_URL##*/tag/}"
  else
    echo "Warning: could not resolve the latest release tag; using 'latest' (re-runs will not roll out new images)."
  fi
fi

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

ensure_terraform

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
  curl -fsSL "$RELEASE_URL/quickstart-aws.tar.gz" -o "$WORK_DIR/quickstart-aws.tar.gz"
  tar -xzf "$WORK_DIR/quickstart-aws.tar.gz" -C "$WORK_DIR" --strip-components=1
  rm "$WORK_DIR/quickstart-aws.tar.gz"
fi

# --- Generate terraform.tfvars ---
cd "$WORK_DIR"

# Convert comma-separated subnets to HCL list
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNETS"
SUBNET_HCL=$(printf ', "%s"' "${SUBNET_ARRAY[@]}")
SUBNET_HCL="[${SUBNET_HCL:2}]"

# Escape a value for an HCL double-quoted string (\ " ${ %{)
hcl_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\${/$${/g' -e 's/%{/%%{/g'
}

# Build logstash_config_variables map
CONFIG_MAP="{"
for key in $CONFIG_KEYS; do
  CONFIG_MAP+=$'\n'"    $key = \"$(hcl_escape "$(get_cfg "$key")")\""
done
CONFIG_MAP+=$'\n'"  }"

# Optional syslog source CIDRs
CIDR_LINE=""
if [[ -n "$ALLOWED_CIDRS" ]]; then
  IFS=',' read -ra CIDR_ARRAY <<< "$ALLOWED_CIDRS"
  CIDR_HCL=$(printf ', "%s"' "${CIDR_ARRAY[@]}")
  CIDR_LINE="allowed_syslog_cidrs = [${CIDR_HCL:2}]"
fi

# terraform.tfvars holds credentials: keep it private
umask 077
cat > terraform.tfvars <<EOF
vpc_id          = "$VPC_ID"
subnet_ids      = $SUBNET_HCL
output_type     = "$OUTPUT_TYPE"
internal_nlb    = $INTERNAL_NLB
syslog_port     = $SYSLOG_PORT
log_profile     = "$LOG_PROFILE"
image_tag       = "$IMAGE_TAG"
$CIDR_LINE
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
