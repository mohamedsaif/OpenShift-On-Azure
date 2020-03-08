# UPI

Using UPI (User Provided Infrastructure) is my recommended approach in enterprise setup of production environments where you have a subscription wide policies that relates to naming, RBAC and tagging among many other requirements that requires more control over the cluster provisioning.

In the UPI, you will be creating/reusing existing:
1. Resource Group
2. Virtual Network
3. Masters Managed Identity
4. Bootstrap Machine (ARM Deployment)
5. Masters (ARM Deployment)
6. OPTIONAL: Workers provisioning (you can do this after the cluster masters are up)

>**NOTE:** Currently I focused only creating private clusters, you might find some issues in creating an external cluster that I'm still working to iron.

## Prepare installation folder

I will copy the installer to the our installation folder

```bash

cp ./openshift-install ./installation
# Change the active folder to the installation
cd installation

```

## Extracting installation configs 

Get some variables from the install-config.yaml:

```bash

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

```

## Scaling workers to zero

In UPI, we would want the installer not to worry about provisioning the worker nodes as they can be provisioned after the masters in several ways (using ignitions and the installer or through OCP console/CLI)

```bash

# Scale workers down to 0 (will be provisioned by us)
python3 -c '
import yaml;
path = "install-config.yaml";
data = yaml.load(open(path));
data["compute"][0]["replicas"] = 0;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

```

## Generating manifests

We want to have access to advanced configurations editing can be achieved by generating the installation manifests

```bash

./openshift-install create manifests

```
This will generate 2 folders, openshift and manifests and a state file (.openshift_install_state.json)

## Modifying the installation

```bash

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
# As of now, i'm copying some additional files to support the UPI resources provision. You might need to adjust the path here depending on your installation folder location
cp -r ../../../provisioning/upi/ .

# Controlling resource naming
# As the installer needs to provision various type of resources, an InfraID is used as prefix in form of (cluster-randomstring)
# You can find them in metadata.json file

# Making infra-id and resource group adjustments (if needed)
# INFRA_ID=ocp-infra
# RESOURCE_GROUP=ocp-aen-rg

# If you made changes to the infra-id or resource group names, run the following
python3 ./upi/setup-manifests.py $RESOURCE_GROUP $INFRA_ID

```

## Generating ignition files

```bash

./openshift-install create ignition-configs #--log-level=debug
# Sample output
# INFO Consuming Master Machines from target directory 
# INFO Consuming Worker Machines from target directory 
# INFO Consuming Common Manifests from target directory 
# INFO Consuming Openshift Manifests from target directory

```

## Visualize folder structure

using tree to plot the folder structure to make sure that all needed files are available

```bash
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

```

## Creating resource group (skip if you will use existing one)

I would recommend using a group that is dedicated for this OCP installation

```bash

az group create --name $RESOURCE_GROUP --location $AZURE_REGION

```

## Creating a managed identity to be used by OCP operators

```bash

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

```

## Uploading files to Azure Storage

Azure storage account will be used to store core-os image, the ignition configs to be consumed by the installer bootstrap VM among other things.

>**NOTE:** If you will be using an existing storage account, please update the access vars to an existing one.

```bash

# removing any dashes '-' in the name as it needs to be all lowercase with no special chars for storage account name
STORAGE_ACC_NAME="$(tr -d "-" <<<$CLUSTER_NAME)"

# creating the storage account
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

```

## Private DNS

```bash

az network private-dns zone create -g $RESOURCE_GROUP -n ${CLUSTER_NAME}.${BASE_DOMAIN}
# Link it to vnet
OCP_VNET_ID=$(az network vnet show -g $RG_VNET --name $OCP_VNET_NAME --query id -o tsv)
az network private-dns link vnet create \
    -g $RESOURCE_GROUP \
    -z ${CLUSTER_NAME}.${BASE_DOMAIN} \
    -n ${INFRA_ID}-network-link \
    -v $OCP_VNET_ID \
    -e false

```

## Load balancers

Load balancers will be used for the masters APIs and the ingress of the workers later.

For now, we are creating the load balancer for the masters only.

```bash

# The following deployment creates internal load balancer in the masters subnet and 2 A records in the private zone
az group deployment create \
    -g $RESOURCE_GROUP \
    --template-file "upi/03_infra-internal-lb.json" \
    --parameters privateDNSZoneName="${CLUSTER_NAME}.${BASE_DOMAIN}" \
    --parameters virtualNetworkResourceGroup="$RG_VNET" \
    --parameters virtualNetworkName="$OCP_VNET_NAME" \
    --parameters masterSubnetName="$MST_SUBNET_NAME" \
    --parameters baseName="$INFRA_ID"

```

### OPTIONAL Public DNS

You can optionally have a public load balancer for the masters if you will use the public DNS

```bash

# The following deployment creates a public-ip and public load balancer
az group deployment create \
    -g $RESOURCE_GROUP \
    --template-file "upi/03_infra-public-lb.json" \
    --parameters baseName="$INFRA_ID"
# Adding A record to the public DNS zone
# If you need a public DNS zone, you should have created one in earlier step
export PUBLIC_IP=`az network public-ip list -g $RESOURCE_GROUP --query "[?name=='${INFRA_ID}-master-pip'] | [0].ipAddress" -o tsv`
az network dns record-set a add-record -g $BASE_DOMAIN_RESOURCE_GROUP -z ${BASE_DOMAIN} -n api.${CLUSTER_NAME} -a $PUBLIC_IP --ttl 60

```

## OCP bootstrap ignition (for internal cluster)

```bash

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

```

## OCP masters ignition (for internal cluster)

```bash

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

```

## Waiting for the bootstrap to finish validation

>**NOTE:** This option will work only if you have put a public DNS or you are running from a jumpbox VM in the same vnet with visibility on the private DNS records

Bootstrap here is used to verify that masters are up and API server is available.

```bash

./openshift-install wait-for bootstrap-complete --log-level debug --dir=./installation

```

Once the bootstrap finishes the validation steps, you can delete its resources:

```bash

# Deleting bootstrap resources
az network nsg rule delete -g $RESOURCE_GROUP --nsg-name ${INFRA_ID}-controlplane-nsg --name bootstrap_ssh_in
az vm stop -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm deallocate -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap --yes
az disk delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap_OSDisk --no-wait --yes
az network nic delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-nic --no-wait
az storage blob delete --account-key $ACCOUNT_KEY --account-name $STORAGE_ACC_NAME --container-name files --name bootstrap.ign
az network public-ip delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-ssh-pip

```

## Next steps

When the API server becomes available, you are basically done with the primary OCP installation. You can use OC client to test the cluster and start the day 1 configurations process (like adding worker nodes, configuration AAD authentication,...)