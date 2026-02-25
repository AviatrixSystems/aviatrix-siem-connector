# Building and Publishing Logstash Container to Azure Container Registry

Azure Container Registry is used as an example here but you can use container registry of your choice.

---

## If deploying to Azure China (ex. China North 3), read below otherwise, skip to "0. Set variables"

To deploy in Azure China (21Vianet), follow these additional steps:

1. **Set Azure China Cloud**
   ```sh
   az cloud set --name AzureChinaCloud
   az login
   ```

2. **Set Variables for China North 3**
   ```sh
   export RESOURCE_GROUP="your-resource-group"
   export LOCATION="chinanorth3"
   export ACR_NAME="${RESOURCE_GROUP}acr"  # ACR names must be globally unique
   export IMAGE_NAME="aviatrix-logstash-sentinel"
   export IMAGE_TAG="latest"
   ```

   export RESOURCE_GROUP="core-rg"
   export LOCATION="chinanorth3"
   export ACR_NAME="aviatrixacr"  # ACR names must be globally unique
   export IMAGE_NAME="aviatrix-logstash-sentinel"
   export IMAGE_TAG="latest"

3. **Use China Registry Endpoint**
   - The registry login server will be `${ACR_NAME}.azurecr.cn` (note `.cn` domain).
   - When tagging and pushing images, use:
     ```sh
     docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ACR_NAME}.azurecr.cn/${IMAGE_NAME}:${IMAGE_TAG}
     docker push ${ACR_NAME}.azurecr.cn/${IMAGE_NAME}:${IMAGE_TAG}
     ```

4. **Update Terraform Configuration**
   - In your `terraform.tfvars`:
     ```hcl
     container_image = "${ACR_NAME}.azurecr.cn/${IMAGE_NAME}:${IMAGE_TAG}"
     location       = "chinanorth3"
     ```

5. **Resource Providers**
   - Ensure required resource providers (e.g., Microsoft.ContainerInstance) are registered in your China subscription.

6. **Note**
   - All Azure endpoints in China use `.azure.cn` domains.
   - You must use an Azure China account and subscription.

---

## 0. Set Variables

Set your variables for consistent naming:

```sh
export RESOURCE_GROUP="your-resource-group"
export LOCATION="westeurope"
export ACR_NAME="${RESOURCE_GROUP}acr"  # ACR names must be globally unique
export IMAGE_NAME="aviatrix-logstash-sentinel"
export IMAGE_TAG="latest"
```

## 1. Create a Resource Group (if needed)

If you don't already have a resource group, create one with:

```sh
az group create --name $RESOURCE_GROUP --location $LOCATION
```

## 2. Create an Azure Container Registry

```sh
az acr create --resource-group $RESOURCE_GROUP \
    --name $ACR_NAME \
    --sku Standard
```

## 3. Enable anonymous container pulling.

We could also create a managed identity assigned to the Azure Container Instance so that it has an IAM role that allows container to be pulled for the Azure Container Registry. As we have no sensitive data, we go for anonymus pulling.

```sh
az acr update --name $ACR_NAME --anonymous-pull-enabled true
```

## 4. Log in to the Container Registry

```sh
az acr login --name $ACR_NAME
```

## 5. Build the Docker Image

```sh
az acr build --registry $ACR_NAME \
    --image ${IMAGE_NAME}:${IMAGE_TAG} .
```

*Alternatively, using Docker CLI:*

```sh
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}
docker push ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}
```

## 6. Verify the Image in ACR

```sh
az acr repository list --name $ACR_NAME --output table
```

## 7. Update Terraform Configuration

Update your `terraform.tfvars` file with the correct container image reference:

```hcl
container_image = "${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
```

For example:

```hcl
container_image = "logstash-aci-acr.azurecr.io/aviatrix-logstash-sentinel:latest"
```