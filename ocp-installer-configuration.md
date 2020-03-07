# Installer Configuration

OCP installer depends on having install-config.yaml file with all the cluster initial configuration. You can have this setup of the first time and then reuse it with slight modification to provision same or additional clusters.

## Generating SSH for the cluster

It is a good practice to have SSH key created and submitted to allow various diagnostics scenarios.

```bash

ssh-keygen -f ~/.ssh/$CLUSTER_NAME-rsa -t rsa -N ''

# Starting ssh-agent and add the key to it (used for diagnostic access to the cluster)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/$CLUSTER_NAME-rsa

```

## Red Hat Pull Secret

In order to install, activate and link the OCP installation to your Red Hat account, you need the Pull Secret.

Visit [Red Hat's website] to obtain it and optionally save it here for future use.

```bash

# Get the json pull secret from RedHat (save it to the installation folder you created)
# https://cloud.redhat.com/openshift/install/azure/installer-provisioned
# To save the pull secret, you can use vi
vi pull-secret.json
# Tip: type i to enter the insert mode, paste the secret, press escape and then type :wq (write and quit)

```

## OCP initial setup steps

Assuming that you already have installer folder with the OCP installer binary there. Move to that folder and create new sub-folder to save the generated installer files there.

```bash

# Change dir to installer
cd installer
# Create a new directory to save installer generated files
mkdir installation

```

## Preparing install-config.yaml file

### First time (no existing install-config.yaml yet)

If this is the first time, you can start by launcing the installer to generate the first install-config:

```bash

# NEW CONFIG: run the create install-config to generate the initial configs
./openshift-install create install-config --dir=./installation
# Sample prompts (Azure subscription details will then be saved and will not be promoted again with future installation using the same machine)
# ? SSH Public Key /home/user_id/.ssh/id_rsa.pub
# ? Platform azure
# ? azure subscription id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ? azure tenant id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ? azure service principal client id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ? azure service principal client secret xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# INFO Saving user credentials to "/home/user_id/.azure/osServicePrincipal.json"
# ? Region westeurope
# ? Base Domain example.com
# ? Cluster Name test
# ? Pull Secret [? for help]

```

### Existing install-config.yaml

Locate the install-config.yaml (I would assume you have it somewhere in your terminal)

# If you have the file somewhere else, just copy the content to the vi
vi install-config.yaml

Now you should have the install-config.yaml located in the ```installer``` folder (not ```installation```). This is important as the OCP installer will delete the file once your started creating the cluster and we want to hang to it.

After adjusting the config file to your specs, copy it out of the (installation) folder

```bash
# For subsequent times, you can copy the saved config to the installation folder
cp ./install-config.yaml ./installation

```

>**NOTE:** Credentials saved to ~/.azure/osServicePrincipal.json for the first time your run the installer create config. 
After that it will not ask again for the SP details
If you have it created some where before, just use again vi to make sure it is correct (or copy the content to the new terminal)
vi ~/.azure/osServicePrincipal.json

### Review

You should review the generated install-config.yaml and tune any parameters before creating the cluster

Now the cluster final configuration are saved to install-config.yaml

To proceed, you have 2 options, IPI or UPI. pick one that fits your need and proceed with the cluster provisioning