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

echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  ACR Name: $ACR_NAME"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
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
echo -e "${BLUE}Step 3: Enabling anonymous pull access...${NC}"
az acr update --name $ACR_NAME --anonymous-pull-enabled true
echo -e "${GREEN}✅ Anonymous pull enabled${NC}"

echo ""
echo -e "${BLUE}Step 4: Logging in to ACR...${NC}"
az acr login --name $ACR_NAME
echo -e "${GREEN}✅ Logged in to ACR${NC}"

echo ""
echo -e "${BLUE}Step 5: Building and pushing image to ACR...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
az acr build --registry $ACR_NAME \
    --image ${IMAGE_NAME}:${IMAGE_TAG} \
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
echo -e "   ${BLUE}container_image = \"${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}\"${NC}"
echo ""
echo "2. Run the deployment:"
echo "   cd ../deploy-public"
echo "   ../scripts/validate-deployment.sh"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo -e "${YELLOW}Registry Details:${NC}"
echo "  Registry: ${ACR_NAME}.azurecr.io"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  Full Path: ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
