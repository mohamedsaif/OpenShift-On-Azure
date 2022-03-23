# Adding Arc extentions
az extension add --name connectedk8s
az extension add --name k8s-extension
# update if extension already exists
az extension update --name connectedk8s
az extension update --name k8s-extension

# Register required resource providers
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation

# validate the registration status
az provider show -n Microsoft.Kubernetes -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ExtendedLocation -o table

# Connect ARO to Arc
# docs: https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster?tabs=azure-cli
# Firewall rules: https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster?tabs=azure-cli#meet-network-requirements
ARC_RG=azure-arc
ARC_LOCATION=westeurope
ARO_CLUSTER_NAME=aro4-weu
ARO_RG=aro4-weu
# Create Azure Arc resource group
az group create --name $ARC_RG --location $ARC_LOCATION

# Before connecting the ARO cluster, we need to make sure that kubeconfig is configured to the target cluster
CLUSTER_URL=$(az aro show -g $ARO_RG -n $ARO_CLUSTER_NAME --query apiserverProfile.url -o tsv)
USER=$(az aro list-credentials -g $ARO_RG -n $ARO_CLUSTER_NAME --query kubeadminUsername -o tsv)
PASSWORD=$(az aro list-credentials -g $ARO_RG -n $ARO_CLUSTER_NAME --query kubeadminPassword -o tsv)
oc login $CLUSTER_URL --username=$USER --password=$PASSWORD

oc adm policy add-scc-to-user privileged system:serviceaccount:azure-arc:azure-arc-kube-aad-proxy-sa

# Create connected cluster
az connectedk8s connect \
  --name $ARO_CLUSTER_NAME \
  --resource-group $ARC_RG \
  --location $LOCATION \
  --tags Datacenter=$LOCATION CountryOrRegion=NL
# look in the output for "provisioningState": "Succeeded"

##################
# Arc Extentions #
##################

# Container Insights - Azure Monitor:
# Docs: https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-enable-arc-enabled-clusters

# Firewall outbound rules:
# Endpoint	                    Port
# *.ods.opinsights.azure.com	443
# *.oms.opinsights.azure.com	443
# dc.services.visualstudio.com	443
# *.monitoring.azure.com	    443
# login.microsoftonline.com	    443

ARO_LOGS_WORKSPACE_NAME=aro4-logs-weu
WORKSPACE_ID=$(az resource list \
                --resource-type Microsoft.OperationalInsights/workspaces \
                --query "[?contains(name, '${ARO_LOGS_WORKSPACE_NAME}')].id" -o tsv)
echo $WORKSPACE_ID

az k8s-extension create \
  --name azuremonitor-containers \
  --cluster-name $ARO_CLUSTER_NAME \
  --resource-group $ARC_RG \
  --cluster-type connectedClusters \
  --extension-type Microsoft.AzureMonitor.Containers \
  --configuration-settings logAnalyticsWorkspaceResourceID=$WORKSPACE_ID

# look in the output for "provisioningState": "Succeeded"
# Validate
az k8s-extension show \
  --name azuremonitor-containers \
  --cluster-name $ARO_CLUSTER_NAME \
  --resource-group $ARC_RG \
  --cluster-type connectedClusters \
  -n azuremonitor-containers

# You might configure the default deployment by adding the following param:
# --configuration-settings  omsagent.resources.daemonset.limits.cpu=150m omsagent.resources.daemonset.limits.memory=600Mi omsagent.resources.deployment.limits.cpu=1 omsagent.resources.deployment.limits.memory=750Mi

# Microsoft Defender
# Docs: https://docs.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-enable?tabs=aks-deploy-portal%2Ck8s-deploy-asc%2Ck8s-verify-asc%2Ck8s-remove-arc%2Caks-removeprofile-api&pivots=defender-for-container-arc

# Make sure that Microsoft Defender for Containers is enabled

# Firewall outbound rules:
# Domain	                    Port
# *.ods.opinsights.azure.com	443
# *.oms.opinsights.azure.com	443
# login.microsoftonline.com	    443

# You can use Microsoft Defender in Azure Portal or Azure CLI to enable the protection
az k8s-extension create \
  --name microsoft.azuredefender.kubernetes \
  --cluster-type connectedClusters \
  --cluster-name $ARO_CLUSTER_NAME \
  --resource-group $ARC_RG \
  --extension-type microsoft.azuredefender.kubernetes \
  --configuration-settings logAnalyticsWorkspaceResourceID=$WORKSPACE_ID auditLogPath="/var/log/kube-apiserver/audit.log"

# Validate
az k8s-extension show \
  --name microsoft.azuredefender.kubernetes \
  --cluster-name $ARO_CLUSTER_NAME \
  --resource-group $ARC_RG \
  --cluster-type connectedClusters \
  -n microsoft.azuredefender.kubernetes

# Microsoft Defender in Azure Portal can help in creating new policy with "DeployIfNotExists" effect through the 
# enfoce button under Microsoft Defender for Cloud -> Your Arc-Connected Cluster -> Defender policy -> Enforce
# Policy template is "Configure Azure Arc enabled Kubernetes clusters to install Azure Defender's extension"
