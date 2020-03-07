# Jump-Box Provision

It is a good practice to have a jump box server to act as your installation terminal (especially if you are creating a private cluster with no access to the vnet). This guid helps you in setting up this VM and I would highly recommend doing so.

If you are using a local dev machine, make sure to follow the installation steps mentioned in this guide to make sure you have all the needed tools.

## Creating new VM

The following steps can be used to provision Ubuntu VM on Azure. 

>**NOTE:** You can skip these steps till (Tooling & configurations) if you intent to use your current machine.

### Generating SSH key pair

```bash

ssh-keygen -f ~/.ssh/installer-box-rsa -m PEM -t rsa -b 4096

```

### Jump-Box subnet

We need the jump-box provisioned in a subnet that have a line-of-sight of the potential OCP cluster.

You can also opt-in to have a separate virtual network that is peered with the OCP cluster network as well.

```bash

# Get the ID for the masters subnet (as it is in a different resource group)
INST_SUBNET_ID=$(az network vnet subnet show -g $RG_VNET --vnet-name $OCP_VNET_NAME --name $INST_SUBNET_NAME --query id -o tsv)

```

>**NOTE:** Above command retrieve an existing subnet id, if you need to create one, please follow the steps in the [OCP-Prerequisites.md] virtual network section.

### Jump-Box resource group

```bash

# Create a resource group to host jump box
OCP_LOCATION_CODE=westeurope
PREFIX=dev
RG_INSTALLER=$PREFIX-installer-rg-$OCP_LOCATION_CODE
az group create --name $RG_INSTALLER --location $OCP_LOCATION

```

### Creating the VM

```
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

```

If you have an existing jump box, just set the public publicIpAddress

```

INSTALLER_PIP=REPLACE_IP

```

### Connecting to the jump-box

#### OPTIONAL: Copy any needed files to target jump-box

Before you connect to the jump-box VM, you can copy any needed files (use this only if you have custom files that you wish to have on the machine like custom install-config files).

```bash

# Zip the installation files that you want to copy to the jump box
# make sure you are in the right folder on the local machine
cd provisioning
tar -pvczf ocp-installation.tar.gz .

scp -i ~/.ssh/installer-box-rsa ./ocp-installation.tar.gz localadmin@$INSTALLER_PIP:~/ocp.tar.gz

```
#### Connecting to the jump-box

```bash
# SSH to the jumpbox
ssh -i ~/.ssh/installer-box-rsa localadmin@$INSTALLER_PIP

```

You might want to clone the GitHub repo as well for the UPI installation files (if you didn't already in the copy step)

```bash

git clone https://github.com/mohamedsaif/OpenShift-On-Azure.git

```

## Tooling & configurations

Now we need to to make sure that all needed tooling is installed/downloaded.

### Azure CLI

```bash
# Installing Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

```

### python3

```bash

sudo apt-get update
sudo apt-get install python3.6
python3 --version

# pip should be installed as part of python 3.6 :)

```

### Installing PyYAML for manipulating yaml files

```bash

sudo pip install -U PyYAML

```

### DotMap (used in manipulating files as well)

```bash

pip install dotmap

```

### jq

```bash

sudo apt-get install jq

```

### yq
```bash

sudo pip install yq

```

### tree (folder visual rep)

```bash

sudo apt-get install tree

```

>**NOTE:** If you faced issues with unrecognized commands, you might consider restarting the VM for some of the tooling to picked up.
```sudo apt-get update```

## Login to Azure

You might need to provision any custom resources before or during the installation, so let's sign in to Azure

```bash

az login

az account set --subscription "SUBSCRIPTION_NAME"

# Make sure the active subscription is set correctly
az account show

# Set the Azure subscription and AAD tenant ids
OCP_TENANT_ID=$(az account show --query tenantId -o tsv)
OCP_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo $OCP_TENANT_ID
echo $OCP_SUBSCRIPTION_ID

```

### OPTIONAL DNS Resolver

If you are using Azure VM, you might want to update the DNS server name to point at Azure DNS fixed IP address (to be able to easily resolve the OCP private DNS FQDNs)

```bash

# Adding Azure DNS server (to handle the private name resoultion)
sudo chmod o+r /etc/resolv.conf

# Edit the DNS server name to use Azure's DNS server fixed IP 168.63.129.16 (press i to be in insert mode, then ESC and type :wq to save and exit)
sudo vi /etc/resolv.conf

```

### OPTIONAL Extract the copied archives

If you have copied any archive to the remote jump-box, you can extract the files now.

```bash

mkdir ocp-installer
tar -xvzf ./ocp.tar.gz -C ./ocp-installer
cd ocp-installer
# Check the extracted files (you should have your config and OCP installer)
ls

```