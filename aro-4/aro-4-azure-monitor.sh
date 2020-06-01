# NOTE: These steps assume that you have oc client tools already signed in into your ARO cluster
# I'm assuming variables from the cluster provisioning are in memory. If not, please run
source ./aro-provision.vars

# Azure Monitor Integration
# Prerequisites:
# Azure CLI v2.0.72+, Helm 3, Bash v4 and kubectl set to OpenShift context
# Docs: https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-azure-redhat4-setup

# Creating new Log Analytics Workspace
# Skip if you will join an existing one
ARO_LOGS_LOCATION=$LOCATION
ARO_LOGS_WORKSPACE_NAME=$CLUSTER-logs-$RANDOM
ARO_LOGS_RG=$ARO_RG
sed logs-workspace-deployment.json \
    -e s/WORKSPACE-NAME/$ARO_LOGS_WORKSPACE_NAME/g \
    -e s/DEPLOYMENT-LOCATION/$ARO_LOGS_LOCATION/g \
    -e s/ENVIRONMENT-VALUE/DEV/g \
    -e s/PROJECT-VALUE/ARO4/g \
    -e s/DEPARTMENT-VALUE/IT/g \
    -e s/STATUS-VALUE/EXPERIMENTAL/g \
    > aro-logs-workspace-deployment-updated.json

# Deployment can take a few mins
ARO_LOGS_WORKSPACE=$(az group deployment create \
    --resource-group $ARO_LOGS_RG \
    --name aro-logs-workspace-deployment \
    --template-file aro-logs-workspace-deployment-updated.json)

ARO_LOGS_WORKSPACE_ID=$(echo $ARO_LOGS_WORKSPACE | jq -r '.properties["outputResources"][].id')

echo export ARO_LOGS_WORKSPACE_ID=$ARO_LOGS_WORKSPACE_ID >> ./aro-provision.vars

# If you are using an existing one, get the ID
# Make sure the ARO_LOGS_WORKSPACE_NAME is reflecting the target workspace name
# ARO_LOGS_WORKSPACE_ID=$(az resource list --resource-type Microsoft.OperationalInsights/workspaces --query "[?contains(name, '${ARO_LOGS_WORKSPACE_NAME}')].id" -o tsv)
# echo export ARO_LOGS_WORKSPACE_ID=$ARO_LOGS_WORKSPACE_ID >> ./aro-provision.vars
# If you are not sure what is the name, you can list them here:
# az resource list --resource-type Microsoft.OperationalInsights/workspaces -o table

# On boarding the cluster to Azure Monitor
# Get the latest installation scripts:
curl -LO https://raw.githubusercontent.com/microsoft/OMS-docker/ci_feature/docs/aroV4/onboarding_azuremonitor_for_containers.sh

# IMPORTANT: Make sure that ARO is the active Kubectl context before executing the script
KUBE_CONTEXT=$(kubectl config current-context)
ARO_CLUSTER_ID=$(az aro show  -g $ARO_RG -n $CLUSTER --query id -o tsv)

bash onboarding_azuremonitor_for_containers.sh $KUBE_CONTEXT $ARO_CLUSTER_ID $ARO_LOGS_WORKSPACE_ID