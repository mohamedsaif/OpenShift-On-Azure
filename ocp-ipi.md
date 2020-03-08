# IPI

Using IPI provides a quick and efficient way to provision clusters but you lose a little bit of control over the provisioned cluster installation.

Use this approach if you don't have strict cluster provisioning policies (like deploying in existing resource group is not possible to my knowledge).

All what you need to use the IPI method, is:
1. Service Principal with appropriate permissions (detailed in the script)
2. Details of the vnet address space and whether it exists or it is new
    - Address space of the vnet
    - Subnet for Masters
    - Subnet for Workers
3. DNS (private or public)
4. Pull secret for cluster activation from your Red Hat account
5. OPTIONAL: SSH key to be used to connect the cluster nodes for diagnostics

>**NOTE:** I'm assuming that you already have the install-config.yaml generated along with Azure service principal configured and saved to ~/.azure/osServicePrincipal.json

## OPTIONAL Generating manifests

If you want to have access to advanced configurations editing (modifying kube-proxy for example) can be achieved by generating the installation manifests

```bash

./openshift-install create manifests --dir=./installation

```

This will generate 2 folders, openshift and manifests and a state file (.openshift_install_state.json)

Check .openshift_install_state.json for a detailed list of configuration and resource names.

You can notice a random string called (InfraID) present in the .openshift_install_state.json configs which will be used to ensure uniqueness of generated resources.

Installer will provision resources in the form of <cluster_name>-<random_string>.

## OPTIONAL Check subscription limits of VM-cores

You might hit some subscription service provisioning limits during the installation (especially if you are using Azure free credits or non-enterprise accounts)

To avoid getting error like:

```bash
# compute.VirtualMachinesClient#CreateOrUpdate: Failure sending request: StatusCode=0 -- Original Error: autorest/azure: Service returned an error. 
# Status=<nil> Code="OperationNotAllowed" Message="Operation results in exceeding quota limits of Core. Maximum allowed: 20, Current in use: 20
# , Additional requested: 8.
```

Solving it limits usually easy, submit a new support request here:
[https://aka.ms/ProdportalCRP/?#create/Microsoft.Support/Parameters/](https://aka.ms/ProdportalCRP/?#create/Microsoft.Support/Parameters/)

Use the following details:
- Type	Service and subscription limits (quotas)
- Subscription	Select target subscription
- Problem type	Compute-VM (cores-vCPUs) subscription limit increases
- Click add new quota details (increase from 20 to 50 as the new quota)

Sometimes it is auto approved :)

If you want to check the current limits for a specific location:
```bash

az vm list-usage -l $OCP_LOCATION -o table

```

## Create the cluster

>**NOTE:** change log level to debug to get further details (other options are warn and error)

```bash

./openshift-install create cluster --dir=./installation --log-level=info

```

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

## Deleting the cluster all generated resources

If cluster needs to be destroyed to be recreated, execute the following:

```bash

./openshift-install destroy cluster --dir=./installation

```
Note that some files might not be removed (like the terraform.tfstate) by the installer. You need to remove them manually

Sample destruction output of fully provisioned cluster
```bash

# INFO deleted                                       record=api.dev-ocp-weu
# INFO deleted                                       record="*.apps.dev-ocp-weu"
# INFO deleted                                       resource group=dev-ocp-weu-fsnm5-rg
# INFO deleted                                       appID=GUID
# INFO deleted                                       appID=GUID
# INFO deleted                                       appID=GUID

```