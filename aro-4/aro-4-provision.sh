# Docs: https://docs.openshift.com/aro/4/welcome/index.html
# Docs: 
# Installing the development version of az aro CLIs

# Making sure you have the Python Tools:
sudo apt-get install python-setuptools

# Maybe also check that you are using the latest Azure CLI :)
sudo apt-get update && sudo apt-get install --only-upgrade -y azure-cli

# Sign in to Azure (if needed)
az login

# Getting the aro extension
az extension add -n aro --index https://az.aroapp.io/stable

# or update an existing extension
az extension update -n aro --index https://az.aroapp.io/stable

# check that the new extension is available
az -v

# Extensions:
# ...
# aro                                1.0.0
# ...

# Registering the Azure Resource Provider for ARO
az provider register -n Microsoft.RedHatOpenShift --wait

# Check the ARO available regions:
az provider show -n Microsoft.RedHatOpenShift --query "resourceTypes[?resourceType == 'OpenShiftClusters']".locations

# Getting Red Hat Pull Secret for accessing OCP market place
# Visit and download pull-secret.txt from   # https://cloud.redhat.com/openshift/install/azure/installer-provisioned/' # [OPTIONAL]
PULL_SECRET=$(<pull-secret.txt)

# Configure installation variables
PREFIX=aro4
LOCATION=southafricanorth # Check the available regions on the ARO roadmap https://aka.ms/aro/roadmap
ARO_RG="$PREFIX-$LOCATION"
ARO_INFRA_RG="$PREFIX-infra-$LOCATION"
VNET_RG="$PREFIX-shared-$LOCATION"

# Cluster information
CLUSTER=$PREFIX-$LOCATION
DOMAIN_NAME=aro4-$RANDOM

# Network details
PROJ_VNET_NAME=aro-vnet
MASTERS_SUBNET_NAME=$CLUSTER-masters
WORKERS_SUBNET_NAME=$CLUSTER-workers
PROJ_VNET_ADDRESS_SPACE=10.166.0.0/23
MASTERS_SUBNET_IP_PREFIX=10.166.0.0/24
WORKERS_SUBNET_IP_PREFIX=10.166.1.0/24

# Installation resource group creation
az group create -g $ARO_RG -l $LOCATION
az group create -g $VNET_RG -l $LOCATION

# We need a vent with 2 empty subnets (no NSGs):
az network vnet create \
    --resource-group $VNET_RG \
    --name $PROJ_VNET_NAME \
    --address-prefixes $PROJ_VNET_ADDRESS_SPACE
    
# Create subnets for masters and workers (with Container Registry service endpoint)
az network vnet subnet create \
    --resource-group $VNET_RG \
    --vnet-name $PROJ_VNET_NAME \
    --name $MASTERS_SUBNET_NAME \
    --address-prefix $MASTERS_SUBNET_IP_PREFIX \
    --service-endpoints Microsoft.ContainerRegistry
  
az network vnet subnet create \
    --resource-group $VNET_RG \
    --vnet-name $PROJ_VNET_NAME \
    --name $WORKERS_SUBNET_NAME \
    --address-prefix $WORKERS_SUBNET_IP_PREFIX \
    --service-endpoints Microsoft.ContainerRegistry


# Currently we need to disable the policies on the private link
az network vnet subnet update \
  -g $VNET_RG \
  --vnet-name $PROJ_VNET_NAME \
  -n $MASTERS_SUBNET_NAME \
  --disable-private-link-service-network-policies true

# or create new SP
ARO_SP=$(az ad sp create-for-rbac -n "${CLUSTER}-aro-sp" --skip-assignment)
echo $ARO_SP | jq
ARO_SP_ID=$(echo $ARO_SP | jq -r .appId)
ARO_SP_PASSWORD=$(echo $ARO_SP | jq -r .password)
ARO_SP_TENANT=$(echo $ARO_SP | jq -r .tenant)
echo $ARO_SP_ID
echo $ARO_SP_PASSWORD
echo $ARO_SP_TENANT

# If you have existing SP (note that SP can be used only with one ARO cluster)
# ARO_SP_ID=
# ARO_SP_PASSWORD=

# Role assignment
az role assignment create --assignee $ARO_SP_ID --role "Contributor" --resource-group $ARO_RG
PROJ_VNET_ID=$(az network vnet show -g $VNET_RG --name $PROJ_VNET_NAME --query id -o tsv)
az role assignment create --assignee $ARO_SP_ID --role "User Access Administrator" --scope $PROJ_VNET_ID

# Check the assignments
az role assignment list \
    --all \
    --assignee $ARO_SP_ID \
    --output json | jq '.[] | {"principalName":.principalName, "roleDefinitionName":.roleDefinitionName, "scope":.scope}'

# Saving variables to a file for later use
echo export PREFIX=aro4 >> ./aro-provision.vars
# Check the available regions on the ARO roadmap https://aka.ms/aro/roadmap
echo export LOCATION=westeurope >> ./aro-provision.vars
echo export ARO_RG=$ARO_RG >> ./aro-provision.vars
echo export ARO_INFRA_RG=$ARO_INFRA_RG >> ./aro-provision.vars
echo export VNET_RG=$VNET_RG >> ./aro-provision.vars
# Cluster information
echo export CLUSTER=$CLUSTER >> ./aro-provision.vars
echo export DOMAIN_NAME=$DOMAIN_NAME >> ./aro-provision.vars
# Network details
echo export PROJ_VNET_NAME=$PROJ_VNET_NAME >> ./aro-provision.vars
echo export MASTERS_SUBNET_NAME=$MASTERS_SUBNET_NAME >> ./aro-provision.vars
echo export WORKERS_SUBNET_NAME=$WORKERS_SUBNET_NAME >> ./aro-provision.vars
echo export PROJ_VNET_ADDRESS_SPACE=$PROJ_VNET_ADDRESS_SPACE >> ./aro-provision.vars
echo export MASTERS_SUBNET_IP_PREFIX=$MASTERS_SUBNET_IP_PREFIX >> ./aro-provision.vars
echo export WORKERS_SUBNET_IP_PREFIX=$WORKERS_SUBNET_IP_PREFIX >> ./aro-provision.vars
# Service Principal
echo export ARO_SP_ID=$ARO_SP_ID >> ./aro-provision.vars
echo export ARO_SP_PASSWORD=$ARO_SP_PASSWORD >> ./aro-provision.vars
echo export ARO_SP_TENANT=$ARO_SP_TENANT >> ./aro-provision.vars
# Creating the cluster
az aro create \
    --resource-group $ARO_RG \
    --cluster-resource-group $ARO_INFRA_RG \
    --name $CLUSTER \
    --location $LOCATION \
    --vnet $PROJ_VNET_NAME \
    --vnet-resource-group $VNET_RG \
    --master-subnet $MASTERS_SUBNET_NAME \
    --worker-subnet $WORKERS_SUBNET_NAME \
    --ingress-visibility Public \
    --apiserver-visibility Public \
    --pull-secret $PULL_SECRET \
    --worker-count 3 \
    --client-id $ARO_SP_ID \
    --client-secret $ARO_SP_PASSWORD \
    --domain $DOMAIN_NAME \
    --tags "PROJECT=ARO4" "STATUS=EXPERIMENTAL" --debug

# In private cluster, I would highly recommend setting up the private DNS by including the following:
# --domain $DOMAIN_NAME

# To create fully private clusters add the following to the create command:
# Ingress controls the visibility of your workloads
# API Server control the visibility of your masters api server
# --ingress-visibility Private \
# --apiserver-visibility Private \

# Check the cluster
az aro list -o table

# To display cluster kubeadmin credentials:
az aro list-credentials -g $ARO_RG -n $CLUSTER

# Get the API server url:
CLUSTER_URL=$(az aro show -g $ARO_RG -n $CLUSTER --query apiserverProfile.url -o tsv)

# Getting the oc CLI tools
mkdir client
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar -xvzf ./openshift-client-linux.tar.gz -C ./client
sudo cp ./client/oc /usr/local/bin/
oc version

# Login to the cluster using the cli
USER=$(az aro list-credentials -g $ARO_RG -n $CLUSTER --query kubeadminUsername -o tsv)
PASSWORD=$(az aro list-credentials -g $ARO_RG -n $CLUSTER --query kubeadminPassword -o tsv)
oc login $CLUSTER_URL --username=$USER --password=$PASSWORD
# test the successful login
oc get nodes

# Scale the cluster to 4 worker nodes
# The easiest way to do this is via the console -> Compute -> Machine Sets -> each worker will have a machine set (usually with different availability zones to optimize the cluster SLA), set the desired count to the target value
# You can also scale manually through the machineset apis
# Get all machinesets
oc get machinesets -n openshift-machine-api
# Scale a particular one to 2 nodes
oc scale --replicas=2 machineset <machineset> -n openshift-machine-api
# NOTE: Having zero worker nodes in your cluster will result be default in losing access to OpenShift console. You will still be able to access the cluster via oc CLI
# NOTE: If you need to cool down the cluster to save cost, I would recommend maintaining at least 2 nodes during that period to avoid hitting problems with cluster operations

# Clean up
az aro delete -g $ARO_RG -n $CLUSTER

# ARO Create options
# Command
#     az aro create : Create a cluster.
#         Command group 'aro' is in preview. It may be changed/removed in a future release.
# Arguments
#     --master-subnet     [Required] : Name or ID of master vnet subnet.  If name is supplied,
#                                      `--vnet` must be supplied.
#     --name -n           [Required] : Name of cluster.
#     --resource-group -g [Required] : Name of resource group. You can configure the default group
#                                      using `az configure --defaults group=<name>`.
#     --worker-subnet     [Required] : Name or ID of worker vnet subnet.  If name is supplied,
#                                      `--vnet` must be supplied.
#     --apiserver-visibility         : API server visibility.
#     --client-id                    : Client ID of cluster service principal.
#     --client-secret                : Client secret of cluster service principal.
#     --cluster-resource-group       : Resource group of cluster.
#     --domain                       : Domain of cluster.
#     --ingress-visibility           : Ingress visibility.
#     --location -l                  : Location. Values from: `az account list-locations`. You can
#                                      configure the default location using `az configure --defaults
#                                      location=<location>`.
#     --master-vm-size               : Size of master VMs.
#     --no-wait                      : Do not wait for the long-running operation to finish.
#     --pod-cidr                     : CIDR of pod network.
#     --service-cidr                 : CIDR of service network.
#     --tags                         : Space-separated tags: key[=value] [key[=value] ...]. Use '' to
#                                      clear existing tags.
#     --vnet                         : Name or ID of vnet.  If name is supplied, `--vnet-resource-
#                                      group` must be supplied.
#     --vnet-resource-group          : Name of vnet resource group.
#     --worker-count                 : Count of worker VMs.
#     --worker-vm-disk-size-gb       : Disk size in GB of worker VMs.
#     --worker-vm-size               : Size of worker VMs.

# Global Arguments
#     --debug                        : Increase logging verbosity to show all debug logs.
#     --help -h                      : Show this help message and exit.
#     --output -o                    : Output format.  Allowed values: json, jsonc, none, table, tsv,
#                                      yaml, yamlc.  Default: json.
#     --query                        : JMESPath query string. See http://jmespath.org/ for more
#                                      information and examples.
#     --subscription                 : Name or ID of subscription. You can configure the default
#                                      subscription using `az account set -s NAME_OR_ID`.
#     --verbose                      : Increase logging verbosity. Use --debug for full debug logs.