# NOTE: These steps assume that you have oc client tools already signed in into your ARO cluster

# Azure Container Registry (ACR) Integration
# It is common on Azure to use ACR for central container registry
# ARO can easily integrate with ACR through SPN and Kubernetes pull secret

# Set the name of existing or new ACR
CONTAINER_REGISTRY_NAME="aroacr$RANDOM"
# If you don't have ACR, you can create one:
az acr create \
    -g $ARO_RG \
    -n $CONTAINER_REGISTRY_NAME \
    --sku Standard \
    --tags "PROJECT=ARO4" "STATUS=EXPERIMENTAL"
# Getting the resource id:
ACR_ID=$(az acr show --name $CONTAINER_REGISTRY_NAME --query id --output tsv)
# Creating service principal
# Create a SP to be used to access ACR (this will be used by Azure DevOps to push images to the registry)
ACR_SP_NAME="${CLUSTER}-acr-sp"
ACR_SP=$(az ad sp create-for-rbac -n $ACR_SP_NAME --skip-assignment)
# echo $ACR_SP | jq
ACR_SP_ID=$(echo $ACR_SP | jq -r .appId)
ACR_SP_PASSWORD=$(echo $ACR_SP | jq -r .password)

echo $ACR_SP_ID
echo $ACR_SP_PASSWORD

# Take a note of the ID and Password values as we will be using them in Azure DevOps

# We need the full ACR Azure resource id to grant the permissions
# No we grant permissions to the SP to allow push and pull roles
az role assignment create --assignee $ACR_SP_ID --scope $ACR_ID --role acrpull
az role assignment create --assignee $ACR_SP_ID --scope $ACR_ID --role acrpush

# Creating the pull secret in ARO
ARO_PULL_SECRET_NAME=default-acr
oc create secret docker-registry $ARO_PULL_SECRET_NAME \
  --namespace default \
  --docker-server=https://$CONTAINER_REGISTRY_NAME.azurecr.io \
  --docker-username=$ACR_SP_ID \
  --docker-password=$ACR_SP_PASSWORD

# OPTIONAL: Import an image to ACR for testing
az acr import \
  --name $CONTAINER_REGISTRY_NAME \
  --source docker.io/library/nginx:latest \
  --image nginx:latest
# Validate the import was successful
az acr repository show-manifests \
  --name $CONTAINER_REGISTRY_NAME \
  --repository nginx

# Deploy from ACR to ARO
# Open the sample deployment file (hello-world-pod.yaml) and replace the #{acrName}# with your ACR name
oc apply -f nginx-pod.yaml
# clean up
oc delete -f nginx-pod.yaml