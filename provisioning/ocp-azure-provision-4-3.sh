#***** Installation Terminal Setup *****

# NOTES:
# UPI part still under development (I need to iron some details).
# If you will use (internal) OCP deployment, I would highly recommend doing this from a jump box deployed in the OCP cluster virtual network.

#***** Installation Terminal Setup *****

# External CLI tools needed:
# Azure CLI (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
# jq (https://stedolan.github.io/jq/)

# Create a directory for your installation
mkdir ocp-4-3-installation
cd ocp-4-3-installation

# Generate SSH key if needed:
ssh-keygen -f ~/.ssh/$CLUSTER_NAME-rsa -t rsa -N ''

# Starting ssh-agent and add the key to it (used for diagnostic access to the cluster)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/$CLUSTER_NAME-rsa

# Obtaining IPI program
# Download the installer/client program from RedHat (save it to the installation folder you created)
# https://cloud.redhat.com/openshift/install/azure/installer-provisioned
# Files will be something like (openshift-client-linux-4.3.2.tar.gz and openshift-install-linux-4.3.2.tar.gz)

# Extract the installer to installer folder
mkdir installer
tar -xvzf ./openshift-install-linux-4.3.2.tar.gz -C ./installer

# If you wish to have it in PATH libs so you can execute it without having it in folder, run this:
# sudo cp ./installer/openshift-install /usr/local/bin/

mkdir client
tar -xvzf ./openshift-client-linux-4.3.2.tar.gz -C ./client

# Get the json pull secret from RedHat (save it to the installation folder you created)
# https://cloud.redhat.com/openshift/install/azure/installer-provisioned
# To save the pull secret, you can use vi
vi pull-secret.json
# Tips: type i to enter the insert mode, paste the secret, press escape and then type :wq (write and quit)

#***** END Installation Terminal Setup *****

#***** Login to Azure Subscription *****

# You need "User Access Administrator" or higher to be able to perform the OCP installation.
# This account will be used to create the "Service Principal" that will be used by the installer to provision the OCP resources

# A browser window will open to complete the authentication :)
az login

az account set --subscription "SUBSCRIPTION_NAME"

# Make sure the active subscription is set correctly
az account show

# Set the Azure subscription and AAD tenant ids
OCP_TENANT_ID=$(az account show --query tenantId -o tsv)
OCP_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo $OCP_TENANT_ID
echo $OCP_SUBSCRIPTION_ID

clear

#***** END Login to Azure Subscription *****

#***** OpenShift Azure Prerequisites *****

# Variables
OCP_LOCATION=westeurope
OCP_LOCATION_CODE=euw
SUBSCRIPTION_CODE=mct
PREFIX=$SUBSCRIPTION_CODE-ocp-dev
RG_SHARED=$PREFIX-shared-rg
RG_VNET=$PREFIX-vnet-rg-$OCP_LOCATION_CODE
RG_INSTALLER=$PREFIX-installer-rg-$OCP_LOCATION_CODE
CLUSTER_NAME=dev-ocp-cluster-$OCP_LOCATION_CODE

DNS_ZONE=subdomain.yourdomain.com

# Create a resource group to host the shared resources (in this setup, we will use it for DNS)
az group create --name $RG_SHARED --location $OCP_LOCATION

# Create a resource group to host the network resources (in this setup, we will use it for vnet)
az group create --name $RG_VNET --location $OCP_LOCATION

# Create a resource group to host the network resources (in this setup, we will use it for vnet)
az group create --name $RG_INSTALLER --location $OCP_LOCATION

### DNS Setup

# OPTION 1: Full delegation of a root domain to Azure DNS Zone
# Create a DNS Zone (for naked or subdomain)
az network dns zone create -g $RG_SHARED -n $DNS_ZONE

# Delegate the DNS Zone by updating the domain registrar Name Servers to point at Azure DNS Zone Name Servers
# Get the NS to be update in the domain registrar (you can create NS records for the naked-domain (@) or subdomain)
az network dns zone show -g $RG_SHARED -n $DNS_ZONE --query nameServers -o table

# Visit the registrar to update the NS records

# Check if the update successful
# It might take several mins for the DNS records to propagate
nslookup -type=SOA $DNS_ZONE

# Response like
# Server: ns1-04.azure-dns.com
# Address: 208.76.47.4

# yoursubdomain.yourdomain.com
# primary name server = ns1-04.azure-dns.com
# responsible mail addr = msnhst.microsoft.com
# serial = 1
# refresh = 900 (15 mins)
# retry = 300 (5 mins)
# expire = 604800 (7 days)
# default TTL = 300 (5 mins)

# Note: some proxies and routers might not prevent the nslookup. 
# Note: You need to make sure that you can get a valid response to nslookup before you proceed.

### End DNS Setup

### OPTIONAL: virtual network setup
# If you have existing vnet, no need to create one, just update the below params with your network configs
# I will be creating the following cluster networking
# average of 50+- pods per node and will be running across 40+- nodes
# Address space: 10.165.0.0/16
# Masters CIDR (): 10.165.0.0/24 (250 addresses)
# Workers CIDR (): 10.165.1.0/24 (250 addresses)

# allocated addresses (/16 means from 0.0 to 255.255). Cluster machine CIRD must be part of it
OCP_VNET_ADDRESS_SPACE="10.165.0.0/16"
OCP_VNET_NAME="spoke-${PREFIX}-${OCP_LOCATION_CODE}"
# Masters subnet (master VMs, ILB, IPI VMs)
MST_SUBNET_IP_PREFIX="10.165.0.0/24"
MST_SUBNET_NAME="mgm-subnet"
# Workers subnet
WRK_SUBNET_IP_PREFIX="10.165.1.0/24"
WRK_SUBNET_NAME="pods-subnet"

az network vnet create \
    --resource-group $RG_VNET \
    --name $OCP_VNET_NAME \
    --address-prefixes $OCP_VNET_ADDRESS_SPACE \
    --subnet-name $MST_SUBNET_NAME \
    --subnet-prefix $MST_SUBNET_IP_PREFIX

# Create subnet for services
az network vnet subnet create \
    --resource-group $RG_VNET \
    --vnet-name $OCP_VNET_NAME \
    --name $WRK_SUBNET_NAME \
    --address-prefix $WRK_SUBNET_IP_PREFIX

# Creating also Network Security Groups
MST_SUBNET_NSG_NAME=$MST_SUBNET_NAME-nsg
az network nsg create \
    --name $MST_SUBNET_NSG_NAME \
    --resource-group $RG_VNET

az network nsg rule create \
    --resource-group $RG_VNET \
    --nsg-name $MST_SUBNET_NSG_NAME \
    --name "apiserver_in" \
    --priority 101 \
    --access Allow \
    --protocol Tcp \
    --direction Inbound \
    --source-address-prefixes $WRK_SUBNET_IP_PREFIX \
    --source-port-ranges '*' \
    --destination-port-ranges 6443 \
    --destination-address-prefixes '*' \
    --description "Allow API Server inbound connection (from workers)"

# If you will use the installer-jumpbox VM, you can create a separate subnet for it
# It will allow you to delete it (or disable it via Network Security Groups after the cluster provisions)
INST_SUBNET_NAME="inst-subnet"
INST_SUBNET_IP_PREFIX="10.165.2.0/24"
az network vnet subnet create \
    --resource-group $RG_VNET \
    --vnet-name $OCP_VNET_NAME \
    --name $INST_SUBNET_NAME \
    --address-prefix $INST_SUBNET_IP_PREFIX

# Provision the jumpbox
# Provisioning of the jumpbox is located in installer-jumpbox.sh

### SP Setup

# Create a SP to be used by OpenShift (no permissions is granted here, it will be granted in the next steps)
OCP_SP=$(az ad sp create-for-rbac -n "${PREFIX}-installer-sp" --skip-assignment)
# As the json result stored in OCP_SP, we use some jq Kung Fu to extract the values 
# jq documentation: (https://shapeshed.com/jq-json/#how-to-pretty-print-json)
echo $OCP_SP | jq
OCP_SP_ID=$(echo $OCP_SP | jq -r .appId)
OCP_SP_PASSWORD=$(echo $OCP_SP | jq -r .password)
OCP_SP_TENANT=$(echo $OCP_SP | jq -r .tenant)
OCP_SP_SUBSCRIPTION_ID=$OCP_SUBSCRIPTION_ID
echo $OCP_SP_ID
echo $OCP_SP_PASSWORD
echo $OCP_SP_TENANT
echo $OCP_SP_SUBSCRIPTION_ID
# Save the above information in a secure location

# Assigning AAD ReadWrite.OwnedBy
az ad app permission add --id $OCP_SP_ID --api 00000002-0000-0000-c000-000000000000 --api-permissions 824c81eb-e3f8-4ee6-8f6d-de7f50d565b7=Role
# Requesting the (Admin Consent) for the permission.
az ad app permission grant --id $OCP_SP_ID --api 00000002-0000-0000-c000-000000000000
# Now by visiting the AAD in Azure portal, you can search for your service principal under "App Registrations" and make sure to grant the admin consent.

# Assigning "Contributor" (for Azure resources creation) and "User Access Administrator" (to grant access to OCP provisioned components)
az role assignment create --assignee $OCP_SP_ID --role "Contributor"
az role assignment create --assignee $OCP_SP_ID --role "User Access Administrator"

# Have a look at SP Azure assignments:
az role assignment list --assignee $OCP_SP_ID -o table

# Saving the SP credentials so the OCP installer will pick the new one without prompting
echo $OCP_SP | jq --arg sub_id $OCP_SUBSCRIPTION_ID '{subscriptionId:$sub_id,clientId:.appId, clientSecret:.password,tenantId:.tenant}' > ~/.azure/osServicePrincipal.json

# If you wish to reset the credentials
# az ad sp credential reset --name $OCP_SP_ID

# Note: 
# OCP IPI installer rely on SP credentials stored in (~/.azure/osServicePrincipal.json). 
# If you run installer before on the current terminal, it will use the service principal from that location
# You can delete this file to instruct the installer to prompt for the SP credentials

#***** OCP Initial Setup Steps *****

# Starting Installer-Provisioned-Infrastructure
# Change dir to installer
cd installer
# Create a new directory to save installer generated files
mkdir installation

# Start the IPI process by creating installation configuration file 
# FIRST TIME: run the create install-config to generate the initial configs
./openshift-install create install-config --dir=./installation
# Sample prompts (Azure subscription details will then be saved and will not be promoted again with future installation using the same machine)
# ? SSH Public Key /home/user_id/.ssh/id_rsa.pub
# ? Platform azure
# ? azure subscription id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ? azure tenant id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ? azure service principal client id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ? azure service principal client secret xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# INFO Saving user credentials to "/home/user_id/.azure/osServicePrincipal.json"
# ? Region centralus
# ? Base Domain example.com
# ? Cluster Name test
# ? Pull Secret [? for help]

# After adjusting the config file to your specs, copy it out of the installation folder for later use
# For subsequent times, you can copy the saved config to the installation folder
# cp ./install-config.yaml ./installation
# One key update I usually do the vnet configuration (using the setup we did earlier or existing vnet)

# Note: Credentials saved to ~/.azure/osServicePrincipal.json for the first time your run the installer. 
# After that it will not ask again for the SP details

# Note: You can review the generated install-config.yaml and tune any parameters before creating the cluster
# Note: You can re-run create install-config commands multiple times to validate your modifications

# Now the cluster final configuration are saved to install-config.yaml

# To proceed, you have 2 options, proceed with IPI or UPI

########## IPI ##########

# Advanced configurations editing (modifying kube-proxy for example) can be achieved by generating the installation manifests
./openshift-install create manifests --dir=./installation
# This will generate 2 folders, openshift and manifests and a state file (.openshift_install_state.json)
# Check .openshift_install_state.json for a detailed list of configuration and resource names.
# InfraID is generated in the form of <cluster_name>-<random_string> and will be used to prefix the name of generated resources
# By updating the InfraID, you can modify the entire provisioned resources names (resource group, load balancers,...)

# Create the cluster based on the above configuration
# change log level to debug to get further details (other options are warn and error)
./openshift-install create cluster --dir=./installation --log-level=info

# You might hit some subscription service provisioning limits:
# compute.VirtualMachinesClient#CreateOrUpdate: Failure sending request: StatusCode=0 -- Original Error: autorest/azure: Service returned an error. 
# Status=<nil> Code="OperationNotAllowed" Message="Operation results in exceeding quota limits of Core. Maximum allowed: 20, Current in use: 20
# , Additional requested: 8.
# Solving it is super easy, submit a new support request here:
# https://aka.ms/ProdportalCRP/?#create/Microsoft.Support/Parameters/
# Use the following details:
# Type	Service and subscription limits (quotas)
# Subscription	Select target subscription
# Problem type	Compute-VM (cores-vCPUs) subscription limit increases
# Click add new quota details (increase from 20 to 50 as the new quota)
# Usually it is auto approved :)
# To view the current limits for a specific location:
az vm list-usage -l $OCP_LOCATION -o table

# By default, a cluster will create:
# Bootstrap:    1 Standard_D4s_v3 vm (removed after install)
# Master Nodes: 3 Standard_D8s_v3 (4 vcpus, 16 GiB memory)
# Worker Nodes: 3 Standard_D2s_v3 ().
# Kubernetes APIs will be located at something like:
# https://api.ocp-azure-dev-cluster.YOURDOMAIN.com:6443/

# Normal installer output
# INFO Consuming Install Config from target directory 
# INFO Creating infrastructure resources...         
# INFO Waiting up to 30m0s for the Kubernetes API at https://api.dev-ocp-weu.YOURDOMAIN.COM:6443... 
# INFO API v1.16.2 up                               
# INFO Waiting up to 30m0s for bootstrapping to complete... 
# INFO Destroying the bootstrap resources...        
# INFO Waiting up to 30m0s for the cluster at https://api.dev-ocp-weu.YOURDOMAIN.COM:6443 to initialize... 
# INFO Waiting up to 10m0s for the openshift-console route to be created... 
# INFO Install complete!                            
# INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=HOME/OpenShift-On-Azure/ocp-4-3-installation/installer/installation/auth/kubeconfig' 
# INFO Access the OpenShift web-console here: https://console-openshift-console.apps.dev-ocp-weu.YOURDOMAIN.COM 
# INFO Login to the console with user: kubeadmin, password: yQLvW-BzmTQ-DY8dx-AZZsY 

########## END IPI ##########

########## UPI ##########

#**** Tooling prerequisites
# In addition to openshift-install and Azure CLI, we need the following tools:
# python3
sudo apt-get update
sudo apt-get install python3.6
python3 --version

# pip should be installed as part of python 3.6 :)
# Installing PyYAML for manipulating yaml files
sudo pip install -U PyYAML

# DotMap
pip install dotmap

# jq
sudo apt-get install jq

# yq
sudo pip install yq

# tree (folder visual rep)
sudo apt-get install tree

# Note: If you faced issues with unrecognized commands, you might consider restarting the VM for some of the tooling to picked up.
sudo apt-get update

#**** END Tooling prerequisites

# I will copy the installer to the our installation folder
cp ./openshift-install ./installation
# Change the active folder to the installation
cd installation

# Get some variables from the install-config.yaml
export CLUSTER_NAME=`yq -r .metadata.name install-config.yaml`
export AZURE_REGION=`yq -r .platform.azure.region install-config.yaml`
export SSH_KEY=`yq -r .sshKey install-config.yaml | xargs`
export BASE_DOMAIN=`yq -r .baseDomain install-config.yaml`
export BASE_DOMAIN_RESOURCE_GROUP=`yq -r .platform.azure.baseDomainResourceGroupName install-config.yaml`
export RG_VNET=`yq -r .platform.azure.networkResourceGroupName install-config.yaml`
export OCP_VNET_NAME=`yq -r .platform.azure.virtualNetwork install-config.yaml`
export MST_SUBNET_NAME=`yq -r .platform.azure.controlPlaneSubnet install-config.yaml`
export WRK_SUBNET_NAME=`yq -r .platform.azure.computeSubnet install-config.yaml`
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AZURE_REGION"
echo "Domain: $BASE_DOMAIN"
echo "Domain RG: $BASE_DOMAIN_RESOURCE_GROUP"
echo "vNet RG: $RG_VNET"
echo "vNet Name: $OCP_VNET_NAME"
echo "Masters Subnet: $MST_SUBNET_NAME"
echo "Workers : $WRK_SUBNET_NAME"

# Scale workers down to 0 (will be provisioned by us)
python3 -c '
import yaml;
path = "install-config.yaml";
data = yaml.load(open(path));
data["compute"][0]["replicas"] = 0;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

# Let the installer to consume the config files and generate deployment manifests
./openshift-install create manifests
# This will generate 2 folders, openshift and manifests and a state file (.openshift_install_state.json)

# Under the openshift folder, we will remove all masters and workers machines/machineset definitions
rm -f openshift/99_openshift-cluster-api_master-machines-*.yaml
rm -f openshift/99_openshift-cluster-api_worker-machineset-*.yaml

# Probably when we set the compute to 0 you saw a warning that installer will make masters schedulable.
# We will revert it back to be unscheduable
python3 -c '
import yaml;
path = "manifests/cluster-scheduler-02-config.yml";
data = yaml.load(open(path));
data["spec"]["mastersSchedulable"] = False;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

# Removing the auto provision of public and private DNS zone from the ingress operator
python3 -c '
import yaml;
path = "manifests/cluster-dns-02-config.yml";
data = yaml.load(open(path));
del data["spec"]["publicZone"];
del data["spec"]["privateZone"];
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

# Capturing the auto generated infra-id and resource group (you can adjust these at a later step)
export INFRA_ID=`yq -r '.status.infrastructureName' manifests/cluster-infrastructure-02-config.yml`
export RESOURCE_GROUP=`yq -r '.status.platformStatus.azure.resourceGroupName' manifests/cluster-infrastructure-02-config.yml`
echo $INFRA_ID
echo $RESOURCE_GROUP
# As of now, i'm copying some additional files to support the UPI resources provision
cp -r ../../../provisioning/upi/ .

# Controlling resource naming
# As the installer needs to provision various type of resources, an InfraID is used as prefix in form of (cluster-randomstring)
# You can find them in metadata.json file

# Making infra-id and resource group adjustments (if needed)
# INFRA_ID=ocp-infra
# RESOURCE_GROUP=ocp-aen-rg

# If you made changes to the infra-id or resource group names, run the following
python3 ./upi/setup-manifests.py $RESOURCE_GROUP $INFRA_ID

# Creating ignition files
./openshift-install create ignition-configs #--log-level=debug
# Sample output
# INFO Consuming Master Machines from target directory 
# INFO Consuming Worker Machines from target directory 
# INFO Consuming Common Manifests from target directory 
# INFO Consuming Openshift Manifests from target directory

# using tree to plot the folder structure
tree
# .
# ├── auth
# │   ├── kubeadmin-password
# │   └── kubeconfig
# ├── bootstrap.ign
# ├── master.ign
# ├── metadata.json
# ├── openshift-install
# ├── upi
# │   ├── 01_vnet.json
# │   ├── 02_storage.json
# │   ├── 03_infra-internal-lb.json
# │   ├── 03_infra-public-lb.json
# │   ├── 04_bootstrap-internal-only.json
# │   ├── 04_bootstrap.json
# │   ├── 05_masters-internal-only.json
# │   ├── 05_masters.json
# │   ├── 06_workers.json
# │   ├── dotmap
# │   │   ├── __init__.py
# │   │   ├── __pycache__
# │   │   │   └── __init__.cpython-36.pyc
# │   │   └── test.py
# │   └── setup-manifests.py
# └── worker.ign

# Creating resource group (skip if you will use existing one)
# I would recommend using a group that is dedicated for this OCP installation
az group create --name $RESOURCE_GROUP --location $AZURE_REGION

# Creating a managed identity to be used by OCP operators
az identity create -g $RESOURCE_GROUP -n ${INFRA_ID}-identity

# Granting the managed identity access to the cluster resource group
export PRINCIPAL_ID=`az identity show -g $RESOURCE_GROUP -n ${INFRA_ID}-identity --query principalId --out tsv`
export RESOURCE_GROUP_ID=`az group show -g $RESOURCE_GROUP --query id --out tsv`
az role assignment create --assignee "$PRINCIPAL_ID" --role 'Contributor' --scope "$RESOURCE_GROUP_ID"

# Incase you are using resources outside the cluster resource, you need to assign the appropriate permissions
# In my case, the vnet is in a different resource group:
MST_SUBNET_ID=$(az network vnet subnet show -g $RG_VNET --vnet-name $OCP_VNET_NAME --name $MST_SUBNET_NAME --query id -o tsv)
WRK_SUBNET_ID=$(az network vnet subnet show -g $RG_VNET --vnet-name $OCP_VNET_NAME --name $WRK_SUBNET_NAME --query id -o tsv)
az role assignment create --assignee $PRINCIPAL_ID --scope $MST_SUBNET_ID --role "Network Contributor"
az role assignment create --assignee $PRINCIPAL_ID --scope $WRK_SUBNET_ID --role "Network Contributor"

# Creating Azure Storage to store the ignition configs to be consumed by the installer bootstrap VM
# removing any - in the name as it needs to be all lowercase with no special chars
STORAGE_ACC_NAME="$(tr -d "-" <<<$CLUSTER_NAME)"
az storage account create -g $RESOURCE_GROUP --location $AZURE_REGION --name $STORAGE_ACC_NAME --kind Storage --sku Standard_LRS
export ACCOUNT_KEY=`az storage account keys list -g $RESOURCE_GROUP --account-name $STORAGE_ACC_NAME --query "[0].value" -o tsv`

# Get RHCOS VHD URL
export VHD_URL=`curl -s https://raw.githubusercontent.com/openshift/installer/release-4.3/data/data/rhcos.json | jq -r .azure.url`
az storage container create --name vhd --account-name $STORAGE_ACC_NAME
az storage blob copy start \
    --account-name $STORAGE_ACC_NAME \
    --account-key $ACCOUNT_KEY \
    --destination-blob "rhcos.vhd" \
    --destination-container vhd --source-uri "$VHD_URL"
# Waiting to the upload to finish
status="unknown"
while [ "$status" != "success" ]
do
  status=`az storage blob show --container-name vhd --name "rhcos.vhd" --account-name $STORAGE_ACC_NAME --account-key $ACCOUNT_KEY -o tsv --query properties.copy.status`
  # progress=`az storage blob show --container-name vhd --name "rhcos.vhd" --account-name $STORAGE_ACC_NAME --account-key $ACCOUNT_KEY -o tsv --query properties.copy.progress`
  echo $status #"(progress: $progress)"
  sleep 30
done

# Uploading bootstrap.ign to a new file container
az storage container create --name files --account-name $STORAGE_ACC_NAME --public-access blob
az storage blob upload \
    --account-name $STORAGE_ACC_NAME \
    --account-key $ACCOUNT_KEY \
    -c "files" -f "bootstrap.ign" -n "bootstrap.ign"

# Creating the OS image to be used for VM provisioning
export VHD_BLOB_URL=`az storage blob url --account-name $STORAGE_ACC_NAME --account-key $ACCOUNT_KEY -c vhd -n "rhcos.vhd" -o tsv`
az group deployment create \
    -g $RESOURCE_GROUP \
    --template-file "upi/02_storage.json" \
    --parameters vhdBlobURL="$VHD_BLOB_URL" \
    --parameters baseName="$INFRA_ID"

# Private DNS
az network private-dns zone create -g $RESOURCE_GROUP -n ${CLUSTER_NAME}.${BASE_DOMAIN}
# Link it to vnet
OCP_VNET_ID=$(az network vnet show -g $RG_VNET --name $OCP_VNET_NAME --query id -o tsv)
az network private-dns link vnet create \
    -g $RESOURCE_GROUP \
    -z ${CLUSTER_NAME}.${BASE_DOMAIN} \
    -n ${INFRA_ID}-network-link \
    -v $OCP_VNET_ID \
    -e false

# Load balancers
# INTERNAL DNS ONLY: You are required to have internal load balancer for the masters (private)
# The following deployment creates internal load balancer in the masters subnet and 2 A records in the private zone
az group deployment create \
    -g $RESOURCE_GROUP \
    --template-file "upi/03_infra-internal-lb.json" \
    --parameters privateDNSZoneName="${CLUSTER_NAME}.${BASE_DOMAIN}" \
    --parameters virtualNetworkResourceGroup="$RG_VNET" \
    --parameters virtualNetworkName="$OCP_VNET_NAME" \
    --parameters masterSubnetName="$MST_SUBNET_NAME" \
    --parameters baseName="$INFRA_ID"

# PUBLIC DNS: You can optionally have a public load balancer for the masters if you will use the public DNS
# The following deployment creates a public-ip and public load balancer
az group deployment create \
    -g $RESOURCE_GROUP \
    --template-file "upi/03_infra-public-lb.json" \
    --parameters baseName="$INFRA_ID"
# Adding A record to the public DNS zone
# If you need a public DNS zone, you should have created one in earlier step
export PUBLIC_IP=`az network public-ip list -g $RESOURCE_GROUP --query "[?name=='${INFRA_ID}-master-pip'] | [0].ipAddress" -o tsv`
az network dns record-set a add-record -g $BASE_DOMAIN_RESOURCE_GROUP -z ${BASE_DOMAIN} -n api.${CLUSTER_NAME} -a $PUBLIC_IP --ttl 60

# Launch the bootstrap
export BOOTSTRAP_URL=`az storage blob url --account-name $STORAGE_ACC_NAME --account-key $ACCOUNT_KEY -c "files" -n "bootstrap.ign" -o tsv`
export BOOTSTRAP_IGNITION=`jq -rcnM --arg v "2.2.0" --arg url $BOOTSTRAP_URL '{ignition:{version:$v,config:{replace:{source:$url}}}}' | base64 -w0`

# Bootstrapping for internal only deployment
az group deployment create -g $RESOURCE_GROUP \
    --template-file "upi/04_bootstrap-internal-only.json" \
    --parameters bootstrapIgnition="$BOOTSTRAP_IGNITION" \
    --parameters sshKeyData="$SSH_KEY" \
    --parameters virtualNetworkResourceGroup="$RG_VNET" \
    --parameters virtualNetworkName="$OCP_VNET_NAME" \
    --parameters masterSubnetName="$MST_SUBNET_NAME" \
    --parameters baseName="$INFRA_ID"

# Masters ignition for internal only deployment
export MASTER_IGNITION=`cat master.ign | base64`
az group deployment create -g $RESOURCE_GROUP \
    --template-file "upi/05_masters-internal-only.json" \
    --parameters masterIgnition="$MASTER_IGNITION" \
    --parameters numberOfMasters=3 \
    --parameters masterVMSize="Standard_D4s_v3" \
    --parameters sshKeyData="$SSH_KEY" \
    --parameters privateDNSZoneName="${CLUSTER_NAME}.${BASE_DOMAIN}" \
    --parameters virtualNetworkResourceGroup="$RG_VNET" \
    --parameters virtualNetworkName="$OCP_VNET_NAME" \
    --parameters masterSubnetName="$MST_SUBNET_NAME" \
    --parameters baseName="$INFRA_ID"

# Waiting for the bootstrap to finish
# This option will work only if you have put a public DNS or you are running from a jumpbox VM in the same vnet
./openshift-install wait-for bootstrap-complete --log-level debug

# Deleting bootstrap resources
az network nsg rule delete -g $RESOURCE_GROUP --nsg-name ${INFRA_ID}-controlplane-nsg --name bootstrap_ssh_in
az vm stop -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm deallocate -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap --yes
az disk delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap_OSDisk --no-wait --yes
az network nic delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-nic --no-wait
az storage blob delete --account-key $ACCOUNT_KEY --account-name $STORAGE_ACC_NAME --container-name files --name bootstrap.ign
az network public-ip delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-ssh-pip

########## END UPI ##########

# Congratulations
# Although it says completed, you might need to give it a few mins to warm up :)

# You can access the web-console as per the instructions provided, but let's try using oc CLI instead
cd ..
cd client

# this step so you will not need to use oc login (you will have a different path)
# export KUBECONFIG=[HOME]/installer/auth/kubeconfig

# basic operations
./oc version
./oc config view
./oc status

# Famous get pods
./oc get pod --all-namespaces

# Our cluster running a kubernetes and OpenShift services by default
./oc get svc
# NAME         TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
# docker-registry ClusterIP   172.30.78.158
# kubernetes   ClusterIP      172.30.0.1   <none>                                 443/TCP   36m
# openshift    ExternalName   <none>       kubernetes.default.svc.cluster.local   <none>    24m

# No selected project for sure
./oc project

# if you are interested to look behind the scene on what is happing, access the logs
cat ./.openshift_install.log

# If cluster needs to be destroyed to be recreated, execute the following:
./openshift-install destroy cluster --dir=./installation
# Note that some files are not removed (like the terraform.tfstate) by the installer. You need to remove them manually
# Sample destruction output of fully provisioned cluster
# INFO deleted                                       record=api.dev-ocp-weu
# INFO deleted                                       record="*.apps.dev-ocp-weu"
# INFO deleted                                       resource group=dev-ocp-weu-fsnm5-rg
# INFO deleted                                       appID=GUID
# INFO deleted                                       appID=GUID
# INFO deleted                                       appID=GUID