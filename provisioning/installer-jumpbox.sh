### OPTIONAL: Create an installation jumpbox
ssh-keygen -f ~/.ssh/installer-box-rsa -m PEM -t rsa -b 4096
# Get the ID for the masters subnet (as it is in a different resource group)
INST_SUBNET_ID=$(az network vnet subnet show -g $RG_VNET --vnet-name $OCP_VNET_NAME --name $INST_SUBNET_NAME --query id -o tsv)

# Create a resource group to host jump box
RG_INSTALLER=$PREFIX-installer-rg-$OCP_LOCATION_CODE
az group create --name $RG_INSTALLER --location $OCP_LOCATION

INSTALLER_PIP=$(az vm create \
    --resource-group $RG_INSTALLER \
    --name installer-box \
    --image UbuntuLTS \
    --subnet $INST_SUBNET_ID \
    --size "Standard_B2s" \
    --admin-username localadmin \
    --ssh-key-values ~/.ssh/installer-box-rsa.pub \
    --query publicIpAddress -o tsv)
export INSTALLER_PIP=$INSTALLER_PIP >> ~/.bashrc
# If you have an existing jumpbox, just set the public publicIpAddress
# INSTALLER_PIP=YOUR_IP

# Zip the installation files that you want to copy to the jumpbox
# make sure you are in the right folder on the local machine
tar -pvczf ocp-installation.tar.gz .

scp -i ~/.ssh/installer-box-rsa ./ocp-installation.tar.gz localadmin@$INSTALLER_PIP:~/ocp.tar.gz

# SSH to the jumpbox
ssh -i ~/.ssh/installer-box-rsa localadmin@$INSTALLER_PIP

# Installing Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure
az login

az account set --subscription "SUBSCRIPTION_NAME"

# Make sure the active subscription is set correctly
az account show

# Set the Azure subscription and AAD tenant ids
OCP_TENANT_ID=$(az account show --query tenantId -o tsv)
OCP_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo $OCP_TENANT_ID
echo $OCP_SUBSCRIPTION_ID

# Extract the installation files
mkdir ocp-installer
tar -xvzf ./ocp.tar.gz -C ./ocp-installer
cd ocp-installer
# Check the extracted files (you should have your config and OCP installer)
ls

# Set the variables from the main script and continue the installation