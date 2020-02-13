
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
# Files will be something like (openshift-client-linux-4.3.0.tar.gz and openshift-install-linux-4.3.0.tar.gz)

# Extract the installer to installer folder
mkdir installer
tar -xvzf ./openshift-install-linux-4.3.0.tar.gz -C ./installer

mkdir client
tar -xvzf ./openshift-client-linux-4.3.0.tar.gz -C ./client

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
OCP_LOCATION=uaenorth
OCP_LOCATION_CODE=aen
SUBSCRIPTION_CODE=mct
PREFIX=$SUBSCRIPTION_CODE-ocp-dev
RG_SHARED=$PREFIX-shared-rg
RG_VNET=$PREFIX-vnet-rg-$OCP_LOCATION_CODE
DNS_ZONE=subdomain.yourdomain.com
CLUSTER_NAME=dev-ocp-cluster-$OCP_LOCATION_CODE

# Create a resource group to host the shared resources (in this setup, we will use it for DNS)
az group create --name $RG_SHARED --location $OCP_LOCATION

# Create a resource group to host the network resources (in this setup, we will use it for vnet)
az group create --name $RG_VNET --location $OCP_LOCATION

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

### vnet setup
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

#***** OCP IPI Configuration *****

# Starting Installer-Provisioned-Infrastructure
# Change dir to installer
cd installer
# Create a new directory to save installer generated files
mkdir installation

# Start the IPI process by creating installation configuration file
./openshift-install create install-config --dir=./installation
# After adjusting the config file to your specs, copy it out of the installation folder for later use
# If you have a copy of the config, you can copy it to the installation folder
# cp ./install-config.yaml ./installation

# Note: Credentials saved to ~/.azure/osServicePrincipal.json for the first time your run the installer. 
# After that it will not ask again for the SP details

# Note: You can review the generated install-config.yaml and tune any parameters before creating the cluster
# Note: You can re-run create install-config commands multiple times to validate your modifications

# Advanced configurations editing (modifying kube-proxy for example) can be achieved by generating the installation manifests
./openshift-install create manifests --dir=./installation
# This will generate 2 folders, openshift () and manifests
# Check also .openshift_install_state.json for a detailed list of configuration and resource names.
# Updating the InfraID can modify the entire providioned resources names (resource group, load balancers,...)

# Now the cluster final configuration are saved to install-config.yaml

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
# INFO Consuming "Install Config" from target directory 
# INFO Creating infrastructure resources...         
# INFO Waiting up to 30m0s for the Kubernetes API at https://api.ocp-dev-ae.salesdynamic.com:6443... 
# INFO API v1.14.6+8d00594 up                       
# INFO Waiting up to 30m0s for bootstrapping to complete... 
# INFO Destroying the bootstrap resources...        
# INFO Waiting up to 30m0s for the cluster at https://api.ocp-dev-ae.salesdynamic.com:6443 to initialize... 
# INFO Waiting up to 10m0s for the openshift-console route to be created... 
# INFO Install complete!                            
# INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/localadmin/aks/AKS-SecureCluster/OCP/OCP-Install/installer/auth/kubeconfig' 
# INFO Access the OpenShift web-console here: https://console-openshift-console.apps.CLUSTER-NAME.DOMAIN-NAME.com 
# INFO Login to the console with user: kubeadmin, password: STju6-SEzcN-Nw8vT-nxdD8 

# Congratulations
# Although it says completed, you might need to give it a few mins to warm up :)

# You can access the web-console as per the instructions provided, but let's try using oc CLI instead
cd ..
cd client

# this step so you will not need to use oc login (you will have a different path)
export KUBECONFIG=/home/localadmin/aks/AKS-SecureCluster/OCP/OCP-Install/installer/auth/kubeconfig

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
# Note that some files are not removed (like the terrafrom.tfstate) by the installer. You need to remove them manually