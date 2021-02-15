RELEASE_NAME=velero-v1.5.2-linux-amd64
wget https://github.com/vmware-tanzu/velero/releases/download/v1.5.2/$RELEASE_NAME.tar.gz
tar -xvf $RELEASE_NAME.tar.gz
sudo cp ./$RELEASE_NAME/velero /usr/local/bin/
velero version

AZURE_BACKUP_RESOURCE_GROUP=Velero_Backups
LOCATION=westeurope
az group create -n $AZURE_BACKUP_RESOURCE_GROUP --location $LOCATION

AZURE_STORAGE_ACCOUNT_ID="velero$(uuidgen | cut -d '-' -f5 | tr '[A-Z]' '[a-z]')"
az storage account create \
    --name $AZURE_STORAGE_ACCOUNT_ID \
    --resource-group $AZURE_BACKUP_RESOURCE_GROUP \
    --sku Standard_GRS \
    --encryption-services blob \
    --https-only true \
    --kind BlobStorage \
    --access-tier Hot

BLOB_CONTAINER=velero-k8s
az storage container create -n $BLOB_CONTAINER --public-access off --account-name $AZURE_STORAGE_ACCOUNT_ID

# Cluster name and resource group
CLUSTER_NAME=aro4-weu
CLUSTER_RG=aro4-weu

# For ARO, you need the resource group
export AZURE_RESOURCE_GROUP=$(az aro show --name $CLUSTER_NAME --resource-group $CLUSTER_RG | jq -r .clusterProfile.resourceGroupId | cut -d '/' -f 5,5)
echo $AZURE_RESOURCE_GROUP
# Subscription and tenant information
SUBSCRIPTION_ACCOUNT=$(az account show)
echo $SUBSCRIPTION_ACCOUNT | jq
# Get the tenant ID
AZURE_TENANT_ID=$(echo $SUBSCRIPTION_ACCOUNT | jq -r .tenantId)
# or use TENANT_ID=$(az account show --query tenantId -o tsv)
echo $AZURE_TENANT_ID
# Get the subscription ID
AZURE_SUBSCRIPTION_ID=$(echo $SUBSCRIPTION_ACCOUNT | jq -r .id)
# or use TENANT_ID=$(az account show --query tenantId -o tsv)
echo $AZURE_SUBSCRIPTION_ID

AZURE_CLIENT_SECRET=$(az ad sp create-for-rbac --name "aro4-velero-sp" --skip-assignments --query 'password' -o tsv)
#  \
# )
az role assignment create --assignee $AZURE_CLIENT_ID --role "Contributor" --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
AZURE_CLIENT_ID=$(az ad sp list --display-name "aro4-velero-sp" --query '[0].appId' -o tsv)
echo $AZURE_CLIENT_ID
az role assignment list \
    --all \
    --assignee $AZURE_CLIENT_ID \
    --output json | jq '.[] | {"principalName":.principalName, "roleDefinitionName":.roleDefinitionName, "scope":.scope}'

cat << EOF  > ./credentials-velero.yaml
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
AZURE_CLOUD_NAME=AzurePublicCloud
EOF

# Installing Velero
velero install \
    --provider azure \
    --plugins velero/velero-plugin-for-microsoft-azure:v1.1.1 \
    --bucket $BLOB_CONTAINER \
    --secret-file ./credentials-velero.yaml \
    --backup-location-config resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID \
    --snapshot-location-config apiTimeout=15m \
    --velero-pod-cpu-limit="0" --velero-pod-mem-limit="0" \
    --velero-pod-mem-request="0" --velero-pod-cpu-request="0"

kubectl logs deployment/velero -n velero

# create a backup of default namespace
NS=default
PROJECT_NAME=ostoy
BACKUP_NAME=$PROJECT_NAME-backup
velero create backup $BACKUP_NAME --include-namespaces=$NS

# Check backup status (look for phase:Completed)
velero backup describe $BACKUP_NAME
velero backup logs $BACKUP_NAME

# Restore
oc get backups -n velero
RESTORE_NAME=$PROJECT_NAME-restore
velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME

# Check the restoring status
oc get restore -n velero $RESTORE_NAME -o yaml
velero restore logs $RESTORE_NAME
# Clean up
kubectl delete namespace/velero clusterrolebinding/velero
kubectl delete crds -l component=velero
