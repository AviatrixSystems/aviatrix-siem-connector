#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Aviatrix Logstash Container Build & Push${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}❌ Error: Dockerfile not found. Please run this script from the logstash-container-build directory.${NC}"
    exit 1
fi

# Default values
DEFAULT_RESOURCE_GROUP="aviatrix-logstash-acr-rg"
DEFAULT_LOCATION="eastus"
DEFAULT_ACR_NAME="avxlogstashacr"
DEFAULT_IMAGE_NAME="aviatrix-logstash-sentinel"
DEFAULT_IMAGE_TAG="latest"
DEFAULT_PLUGIN_VERSION=""

# Prompt for values or use defaults
echo -e "${YELLOW}Enter configuration (press Enter to use defaults):${NC}"
echo ""

read -p "Resource Group [$DEFAULT_RESOURCE_GROUP]: " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}

read -p "Location [$DEFAULT_LOCATION]: " LOCATION
LOCATION=${LOCATION:-$DEFAULT_LOCATION}

read -p "ACR Name [$DEFAULT_ACR_NAME]: " ACR_NAME
ACR_NAME=${ACR_NAME:-$DEFAULT_ACR_NAME}

read -p "Image Name [$DEFAULT_IMAGE_NAME]: " IMAGE_NAME
IMAGE_NAME=${IMAGE_NAME:-$DEFAULT_IMAGE_NAME}

read -p "Image Tag [$DEFAULT_IMAGE_TAG]: " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-$DEFAULT_IMAGE_TAG}

read -p "Sentinel plugin version to pin (empty = latest, not reproducible) [$DEFAULT_PLUGIN_VERSION]: " PLUGIN_VERSION
PLUGIN_VERSION=${PLUGIN_VERSION:-$DEFAULT_PLUGIN_VERSION}

read -p "Enable ANONYMOUS pull on the registry (makes every repo in it public)? (y/N): " ANON_PULL
ANON_PULL=${ANON_PULL:-N}

# Registry login server suffix differs in Azure China
if [ "$(az cloud show --query name -o tsv 2>/dev/null)" = "AzureChinaCloud" ]; then
    ACR_SUFFIX="azurecr.cn"
else
    ACR_SUFFIX="azurecr.io"
fi
LOGIN_SERVER="${ACR_NAME}.${ACR_SUFFIX}"

echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  ACR Name: $ACR_NAME"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  Plugin version: ${PLUGIN_VERSION:-latest}"
echo "  Anonymous pull: ${ANON_PULL}"
echo "  Login server: ${LOGIN_SERVER}"
echo ""

read -p "Proceed with this configuration? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${BLUE}Step 1: Checking if resource group exists...${NC}"
if az group show --name $RESOURCE_GROUP &>/dev/null; then
    echo -e "${GREEN}✅ Resource group '$RESOURCE_GROUP' already exists${NC}"
else
    echo -e "${YELLOW}Creating resource group '$RESOURCE_GROUP'...${NC}"
    az group create --name $RESOURCE_GROUP --location $LOCATION
    echo -e "${GREEN}✅ Resource group created${NC}"
fi

echo ""
echo -e "${BLUE}Step 2: Checking if Azure Container Registry exists...${NC}"
if az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP &>/dev/null; then
    echo -e "${GREEN}✅ ACR '$ACR_NAME' already exists${NC}"
else
    echo -e "${YELLOW}Creating Azure Container Registry '$ACR_NAME'...${NC}"
    az acr create --resource-group $RESOURCE_GROUP \
        --name $ACR_NAME \
        --sku Standard
    echo -e "${GREEN}✅ ACR created${NC}"
fi

echo ""
if [[ $ANON_PULL =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Step 3: Enabling anonymous pull access...${NC}"
    az acr update --name "$ACR_NAME" --anonymous-pull-enabled true
    echo -e "${GREEN}✅ Anonymous pull enabled${NC}"
else
    echo -e "${BLUE}Step 3: Skipping anonymous pull (recommended).${NC}"
    echo -e "${YELLOW}   Set container_registry_server/username/password in terraform.tfvars so ACI can pull.${NC}"
    echo -e "${YELLOW}   e.g. create a pull-only ACR token:${NC}"
    echo "   az acr token create --name aci-pull --registry $ACR_NAME --scope-map _repositories_pull"
fi

echo ""
echo -e "${BLUE}Step 4: Logging in to ACR...${NC}"
az acr login --name $ACR_NAME
echo -e "${GREEN}✅ Logged in to ACR${NC}"

echo ""
echo -e "${BLUE}Step 5: Building and pushing image to ACR...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
az acr build --registry "$ACR_NAME" \
    --image "${IMAGE_NAME}:${IMAGE_TAG}" \
    --build-arg "SENTINEL_PLUGIN_VERSION=${PLUGIN_VERSION}" \
    --file Dockerfile \
    .
echo -e "${GREEN}✅ Image built and pushed successfully${NC}"

echo ""
echo -e "${BLUE}Step 6: Verifying image in ACR...${NC}"
az acr repository show --name $ACR_NAME --repository ${IMAGE_NAME}
echo -e "${GREEN}✅ Image verified in ACR${NC}"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✅ Build and Push Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Update your terraform.tfvars with:"
echo -e "   ${BLUE}container_image = \"${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}\"${NC}"
if [[ ! $ANON_PULL =~ ^[Yy]$ ]]; then
    echo -e "   ${BLUE}container_registry_server   = \"${LOGIN_SERVER}\"${NC}"
    echo -e "   ${BLUE}container_registry_username = \"<token or admin user>\"${NC}"
    echo -e "   ${BLUE}container_registry_password = \"<password>\"${NC}"
fi
echo ""
echo "2. Run the deployment:"
echo "   cd ../deploy-public"
echo "   ../scripts/validate-deployment.sh"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo -e "${YELLOW}Registry Details:${NC}"
echo "  Registry: ${LOGIN_SERVER}"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  Full Path: ${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
