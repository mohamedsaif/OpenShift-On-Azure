az login
LOCATION=southafricanorth
CLUSTER_NAME=aroclusterza

APPID="ed35b109-77dc-4633-bfbf-b45c578db6a9"
GROUPID="70c8d357-11e5-4f02-a5d3-ba685c4a2da9"
SECRET="tIsdOX68t[tWZcvRrwpT]3T=TM2MqCF_"
TENANT="4dcb6b3c-dea4-4178-afa1-1a15f96bf779"

az feature register --namespace Microsoft.ContainerService -n AROGA
az provider register -n Microsoft.ContainerService

az group create --name $CLUSTER_NAME --location $LOCATION

# vnet to peer
VNET_ID=$(az network vnet show -n {VNET name} -g {VNET resource group} --query id -o tsv)

WORKSPACE_ID=$(az monitor log-analytics workspace show -g {RESOURCE_GROUP} -n {NAME} --query id -o tsv)

az openshift create \
    --resource-group $CLUSTER_NAME \
    --name $CLUSTER_NAME \
    -l $LOCATION \
    --aad-client-app-id $APPID \
    --aad-client-app-secret $SECRET \
    --aad-tenant-id $TENANT \
    --customer-admin-group-id $GROUPID

az openshift show -n $CLUSTER_NAME -g $CLUSTER_NAME

# CLI Installation
cd
mkdir lib
cd lib
mkdir oc311
cd oc311
curl https://mirror.openshift.com/pub/openshift-v3/clients/3.11.154/linux/oc.tar.gz --output oc.tar.gz
tar -xzf oc.tar.gz
ls

