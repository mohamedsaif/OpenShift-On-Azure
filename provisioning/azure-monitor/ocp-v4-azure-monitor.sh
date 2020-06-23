# Azure Monitor Integration
# Prerequisites:
# Azure CLI v2.0.72+, Helm 3, Bash v4 and kubectl set to OpenShift context
# Docs: https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-azure-redhat4-setup

# Installing Helm 3


# Creating new Log Analytics Workspace
# Skip if you will join an existing one
# Update the below variables to the desired values before execution
OCP_LOGS_LOCATION=westeurope
OCP_LOGS_WORKSPACE_NAME=ocp4-logs-$RANDOM
OCP_LOGS_RG=REPLACE_RESOURCE_GROUP_NAME
sed logs-workspace-deployment.json \
    -e s/WORKSPACE-NAME/$OCP_LOGS_WORKSPACE_NAME/g \
    -e s/DEPLOYMENT-LOCATION/$OCP_LOGS_LOCATION/g \
    -e s/ENVIRONMENT-VALUE/DEV/g \
    -e s/PROJECT-VALUE/OCP4/g \
    -e s/DEPARTMENT-VALUE/IT/g \
    -e s/STATUS-VALUE/EXPERIMENTAL/g \
    > ocp-logs-workspace-deployment-updated.json

# Deployment can take a few mins
OCP_LOGS_WORKSPACE=$(az group deployment create \
    --resource-group $OCP_LOGS_RG \
    --name ocp-logs-workspace-deployment \
    --template-file ocp-logs-workspace-deployment-updated.json)

OCP_LOGS_WORKSPACE_ID=$(echo $OCP_LOGS_WORKSPACE | jq -r '.properties["outputResources"][].id')

echo export OCP_LOGS_WORKSPACE_ID=$OCP_LOGS_WORKSPACE_ID >> ./ocp-provision.vars

# If you are using an existing one, get the ID
# Make sure the OCP_LOGS_WORKSPACE_NAME is reflecting the target workspace name
# OCP_LOGS_WORKSPACE_ID=$(az resource list --resource-type Microsoft.OperationalInsights/workspaces --query "[?contains(name, '${OCP_LOGS_WORKSPACE_NAME}')].id" -o tsv)
# echo export OCP_LOGS_WORKSPACE_ID=$OCP_LOGS_WORKSPACE_ID >> ./ocp-provision.vars
# If you are not sure what is the name, you can list them here:
# az resource list --resource-type Microsoft.OperationalInsights/workspaces -o table

# On boarding the cluster to Azure Monitor
# Get the latest installation scripts:
curl -LO https://raw.githubusercontent.com/microsoft/OMS-docker/ci_feature_prod/docs/openshiftV4/onboarding_azuremonitor_for_containers.sh

# This should be invoked with 4 arguments:
# azureSubscriptionId, azureRegionforLogAnalyticsWorkspace, clusterName and kubeContext name
# I'm getting the subscription id from the signed in account:
OCP_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
CLUSTER_NAME=ocp4-cluster
KUBE_CONTEXT=$(kubectl config current-context)
ARO_CLUSTER_ID=$(az aro show  -g $ARO_RG -n $CLUSTER --query id -o tsv)

bash onboarding_azuremonitor_for_containers.sh $OCP_SUBSCRIPTION_ID $OCP_LOGS_LOCATION $CLUSTER_NAME $KUBE_CONTEXT $ARO_LOGS_WORKSPACE_ID