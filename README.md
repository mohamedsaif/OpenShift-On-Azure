# OpenShift 4.x on Azure IaaS

Provisioning Red Hat OpenShift Container Platform 4.x (starting from 4.2) on Azure IaaS using the Red Hat's official Installer (Installer Provisioned Infrastructure or IPI)

By the end of this guid, the following OCP cluster will be provisioned:

![ocp-azure](res/ocp-azure-architecture.png)

## Azure CLI

Azure CLI is my prefered way to provision resources on Azure as it provide readable and repeatable steps to create multiple environments.

I will use Azure Cloud Shell to do that. Visit [Azure Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/overview) documentation for further details, or visit [shell.azure.com](https://shell.azure.com) if you know your way around.

You can also use your favorite terminal as well (I use VS Code with WSL:Ubuntu under Windows 10 and tmux terminal)

We will be using bash scripts.

It is easy to access the Cloud Shell from withing the Azure Portal:

![cloud-shell](res/cloud-shell.png)

## Prerequisites 

To use Red Hat installer, you need to prepare in advance few prerequisites.

### 0. Create a Resource Group

You can use the Azure Portal or Azure CLI to accomplish this. I will include the CLI command below

```bash

# Setting Variables
PREFIX=ocp-azure
RG=$PREFIX-rg
LOCATION=uaenorth
DNS_ZONE=YOUR-DOMAIN.com

#***** Login to Azure Subscription *****
# A browser window will open to complete the authentication :)
# If you are using Azure Cloud Shell, you can skip this step as you already signed in
az login

# Make sure that the active Subscription is set (in case you have access to multiple subscription)
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

# Create a resource group
az group create --name $RG --location $LOCATION

```

### 1. DNS Name

You need to have control over a top level domain name with one of the registrars (like YOUR-COMPANY.com).

The following steps details how delegation can be accomplished using Azure Portal or Azure CLI (I prefer CLI)

#### 1.1.A Azure DNS Delegation Using Azure Portal

In order delegate this domain management to Azure DNS, first you need to create a new Azure DNS zone.

Head to [portal.azure.com](https://portal.azure.com) and sign in.

Navigate to Create a resource > Networking > DNS zone to open the Create DNS zone page.

![new-dns](res/new-dns-zone.png)

In the **Create DNS Zone** page, set the following information:

- **Resource Group**: name of the resource group where the DNS Zone resource will be provisioned
- **Name**: your domain name (like YOUR-COMPANY.com)
- **Location**: the location of if the provisioned resource (like West Europe)

In a few seconds the provision will be completed, navigate to the created DNS Zone to get the list of the Name Servers.

![dns-zone-ns](res/dns-zone-ns.png)

#### 1.1.B Azure DNS Using Azure CLI

```bash

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

# Reponse like
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

```

#### 1.2 Update Domain Registrar Name Servers

Now visit your domain registrar DNS Management page and update the Name Servers for that domain using the provided Azure Name Servers. 

This essentially will make Azure DNS delegated to managed the domain records.

### 2. Service Principal

Now we need a Service Principal to be used by the installer to provision the Azure infrastructure (like creating VMs)

I will use Azure Cloud Shell to do that.

You can also use your favorite terminal as well.

We will be using bash scripts.

Below is the scripts needs to be run.

#### 2.1 Login to Azure CLI

```bash

#***** Login to Azure Subscription *****
# A browser window will open to complete the authentication :)
# If you are using Azure Cloud Shell, you can skip this step as you already signed in
az login

# Make sure that the active Subscription is set (in case you have access to multiple subscription)
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


```

#### 2.2 Service Principal Creation

```bash

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

# Save the following values to a protected location as you will need them during the use of the installer
echo $OCP_SP_ID
echo $OCP_SP_PASSWORD
echo $OCP_SP_TENANT
echo $OCP_SP_SUBSCRIPTION_ID

# Or create the SP and save the information to file
# az ad sp create-for-rbac --role Owner --name team-installer | jq --arg sub_id "$(az account show | jq -r '.id')" '{subscriptionId:$sub_id,clientId:.appId, clientSecret:.password,tenantId:.tenant}' > ~/.azure/osServicePrincipal.json

# Assigning AAD ReadWrite.OwnedBy
az ad app permission add --id $OCP_SP_ID --api 00000002-0000-0000-c000-000000000000 --api-permissions 824c81eb-e3f8-4ee6-8f6d-de7f50d565b7=Role

# Granting the AAD permission (Admin Consent required). 
# You can double check on Azure Portal to make sure the admin consent was granted
az ad app permission grant --id $OCP_SP_ID --api 00000002-0000-0000-c000-000000000000

# Assigning (Contributor or Owner) and "User Access Administrator"
az role assignment create --assignee $OCP_SP_ID --role "Owner"
# Or: az role assignment create --assignee $OCP_SP_ID --role "Contributor"
az role assignment create --assignee $OCP_SP_ID --role "User Access Administrator"

# Have a look at SP Azure assignments:
az role assignment list --assignee $OCP_SP_ID -o table

# If you wish to reset the credentials
# az ad sp credential reset --name $OCP_SP_ID

```

