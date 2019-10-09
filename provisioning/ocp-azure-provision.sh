# Variables
PREFIX=ocp-azure
RG=$PREFIX-rg
LOCATION=uaenorth
DNS_ZONE=salesdynamic.com

#***** Login to Azure Subscription *****
# A browser window will open to complete the authentication :)
az login

az account set --subscription "SUBSCRIPTION_NAME"

#Make sure the active subscription is set correctly
az account show

# Set the tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo $TENANT_ID
echo $SUBSCRIPTION_ID

clear

#***** END Login to Azure Subscription *****

#***** OpenShift Prerequisites *****

# Create a resource group
az group create --name $RG --location $LOCATION

### DNS Setup

# OPTION 1: Full delegation of a root domain to Azure DNS Zone
# Create a DNS Zone
az network dns zone create -g $RG -n $DNS_ZONE


# Delegate the DNS Zone by updating the Name Servers to Azure DNS Zone Name Servers
# Get the NS
az network dns zone show -g $RG -n $DNS_ZONE --query nameServers -o table

# Visit the registrar to update the NS records

# Check if the update successful, it might take several mins
nslookup -type=SOA $DNS_ZONE

# Response like
# Server: ns1-04.azure-dns.com
# Address: 208.76.47.4

# contoso.net
# primary name server = ns1-04.azure-dns.com
# responsible mail addr = msnhst.microsoft.com
# serial = 1
# refresh = 900 (15 mins)
# retry = 300 (5 mins)
# expire = 604800 (7 days)
# default TTL = 300 (5 mins)

# OPTION 2: Using subdomain
# Create a DNS Zone for subdomain
az network dns zone create -g $RG -n ocp-dev.$DNS_ZONE

### End DNS Setup

### SP Setup

# Create a SP to be used by OpenShift
OCP_SP=$(az ad sp create-for-rbac -n "${PREFIX}-installer-sp" --skip-assignment)
# As the json result stored in OCP_SP, we use some jq Kung Fu to extract the values 
# jq documentation: (https://shapeshed.com/jq-json/#how-to-pretty-print-json)
echo $OCP_SP | jq
OCP_SP_ID=$(echo $OCP_SP | jq -r .appId)
OCP_SP_PASSWORD=$(echo $OCP_SP | jq -r .password)
OCP_SP_TENANT=$(echo $OCP_SP | jq -r .tenant)
OCP_SP_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
echo $OCP_SP_ID
echo $OCP_SP_PASSWORD
echo $OCP_SP_TENANT
echo $OCP_SP_SUBSCRIPTION_ID
# Or create the SP and save the information to file
# az ad sp create-for-rbac --role Owner --name team-installer | jq --arg sub_id "$(az account show | jq -r '.id')" '{subscriptionId:$sub_id,clientId:.appId, clientSecret:.password,tenantId:.tenant}' > ~/.azure/osServicePrincipal.json

# Assigning AAD ReadWrite.OwnedBy
az ad app permission add --id $OCP_SP_ID --api 00000002-0000-0000-c000-000000000000 --api-permissions 824c81eb-e3f8-4ee6-8f6d-de7f50d565b7=Role
# Granting the AAD permission (Admin Consent). You can double check on Azure Portal to make sure the admin consent was granted
az ad app permission grant --id $OCP_SP_ID --api 00000002-0000-0000-c000-000000000000

# Assigning Contributor and "User Access Administrator"
az role assignment create --assignee $OCP_SP_ID --role "Owner"
# Or: az role assignment create --assignee $OCP_SP_ID --role "Contributor"
az role assignment create --assignee $OCP_SP_ID --role "User Access Administrator"

# Have a look at SP Azure assignments:
az role assignment list --assignee $OCP_SP_ID -o table

# If you wish to reset the credentials
# az ad sp credential reset --name $OCP_SP_ID

# Have an ssh key ready to be used
# ssh-keygen -f ~/.ssh/openshift_rsa -t rsa -N ''

# Download the installer/client program from RedHat
# https://cloud.redhat.com/openshift/install/azure/installer-provisioned

# Get the json pull secret from RedHat
# https://cloud.redhat.com/openshift/install/azure/installer-provisioned

# Upload the files downloaded through Azure Cloud Shell or save tar.gz files to a folder if you are using client terminal (like OCP-Install)

# Extract the installer to installer folder
mkdir installer
tar -xvzf ./openshift-install-linux-4.2.0-0.nightly-2019-09-23-115152.tar.gz -C ./installer

mkdir client
tar -xvzf ./openshift-client-linux-4.2.0-0.nightly-2019-09-23-115152.tar.gz -C ./client

# Starting Installer-Provisioned-Infrastructure
# Change dir to installer
cd installer
./openshift-install create install-config

# Note: Credentials saved to /home/localadmin/.azure/osServicePrincipal.json

# Note: You can review the generated install-config.yaml and tune any parameters before creating the cluster

# Now the cluster configuration are saved to install-config.yaml

# Create the cluster based on the above configuration
./openshift-install create cluster

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
az vm list-usage -l $LOCATION -o table

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
./openshift-install destroy cluster
# Note that some files are not removed (like the terrafrom.tfstate) by the installer. You need to remove them manually