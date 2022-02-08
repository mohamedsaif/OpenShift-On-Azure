# You can use several network firewall
# This guide assumes you are using Azure Firewall

# Variables
FW_RG=central-infosec-ent-weu
FW_NAME=hub-ext-fw-ent-weu

FW_PUBLIC_IP=$(az network public-ip show --ids $(az network firewall show -g $FW_RG -n $FW_NAME --query "ipConfigurations[0].publicIpAddress.id" -o tsv) --query "ipAddress" -o tsv)
FW_PRIVATE_IP=$(az network firewall show -g $FW_RG -n $FW_NAME --query "ipConfigurations[0].privateIpAddress" -o tsv)

echo $FW_PUBLIC_IP
echo $FW_PRIVATE_IP
20.50.214.65
az network route-table create -g $FW_RG --name aro-route
az network route-table route create -g $FW_RG --name aro-fw-udr --route-table-name aro-route --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FW_PRIVATE_IP

# required rules
az network firewall application-rule create -g $FW_RG -f $FW_NAME \
 --collection-name 'OpenShift' \
 --action allow \
 --priority 500 \
 -n 'required' \
 --source-addresses '*' \
 --protocols 'http=80' 'https=443' \
 --target-fqdns 'registry.redhat.io' '*.quay.io' 'sso.redhat.com' 'management.azure.com' 'mirror.openshift.com' 'api.openshift.com' 'quay.io' '*.blob.core.windows.net' 'gcs.prod.monitoring.core.windows.net' 'registry.access.redhat.com' 'login.microsoftonline.com' '*.servicebus.windows.net' '*.table.core.windows.net' 'grafana.com'

# Optional rule for Docker
az network firewall application-rule create -g $FW_RG -f $FW_NAME \
 --collection-name 'Docker' \
 --action allow \
 --priority 501 \
 -n 'docker' \
 --source-addresses '*' \
 --protocols 'http=80' 'https=443' \
 --target-fqdns '*cloudflare.docker.com' '*registry-1.docker.io' 'apt.dockerproject.org' 'auth.docker.io'

az network firewall network-rule create  \
    -g $RG_INFOSEC\
    --f $FW_NAME \
    --collection-name "azure-services-rules" \
    -n "service-tags" \
    --source-addresses "*" \
    --protocols "Any" \
    --destination-addresses "AzureContainerRegistry" "MicrosoftContainerRegistry" "AzureActiveDirectory" \
    --destination-ports "*" \
    --action "Allow" \
    --priority 230

# required rules for public clusters
az network firewall network-rule create -g $FW_RG -f $FW_NAME \
 --collection-name 'OpenShift-Public' \
 --action allow \
 --priority 502 \
 -n 'required-public' \
 --source-addresses '6443' \
 --destination-ports "6443" \
 --destination-addresses "52.143.13.154"\
 --protocols "TCP"


# Get the route table id
ROUTE_ID=$(az network route-table show -g $FW_RG --name aro-route --query id -o tsv)

# Avoid adding the UDR on the masters subnet incase of a public cluster.
az network vnet subnet update -g $VNET_RG --vnet-name $PROJ_VNET_NAME --name $MASTERS_SUBNET_NAME --route-table $ROUTE_ID
az network vnet subnet update -g $VNET_RG --vnet-name $PROJ_VNET_NAME --name $WORKERS_SUBNET_NAME --route-table $ROUTE_ID

# Test
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: centos
spec:
  containers:
  - name: centos
    image: centos
    ports:
    - containerPort: 80
    command:
    - sleep
    - "3600"
EOF

oc exec -it centos -- /bin/bash
curl www.google.com