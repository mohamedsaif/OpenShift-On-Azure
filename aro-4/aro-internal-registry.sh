# Ensure registry is exposed on default router
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

# Checking registry pods
oc get pods -n openshift-image-registry
oc logs deployments/image-registry -n openshift-image-registry --tail 10



# Replacing existing registry storage:
# Create a new blob container named image-registry in the storage account first
STORAGE_KEY=1XHjLZsQQwgZT4tAA0TGsvR576AmjXPJFK1p88SgazWUZu0x1dZsbCF+Ms2rTwkAoMZ+DK8Aszy5+AStA81wAg==
oc create secret generic image-registry-private-configuration-user --from-literal=REGISTRY_STORAGE_AZURE_ACCOUNTKEY=$STORAGE_KEY --namespace openshift-image-registry
# Registry storage config
oc edit configs.imageregistry.operator.openshift.io/cluster
acrteststorageaccount
# section to be edited
# storage:
#   azure:
#     accountName: <storage-account-name>
#     container: <container-name>


REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
echo $REGISTRY_HOST

oc policy add-role-to-user registry-editor kubeadmin

# Using pod man
podman login -u kubeadmin -p $(oc whoami -t) --tls-verify=false $REGISTRY_HOST 

# Using docker
# You need to configure the docker daemon like:
# {
#   ...,
#   "insecure-registries": [
#     "registry.fqdn.com",
#     "registry.fqdn.com:5000"
#   ]
# }
docker login -u kubeadmin -p $(oc whoami -t) $REGISTRY_HOST

# Sample image pull/tag/push
OCP_PROJECT=ocp-samples
oc new-project $OCP_PROJECT
docker pull openshift/hello-openshift
docker pull quay.io/ostoylab/ostoy-frontend:1.4.0
docker tag quay.io/ostoylab/ostoy-frontend:1.4.0 $REGISTRY_HOST/$OCP_PROJECT/ostoy-frontend:1.4.0

podman tag quay.io/ostoylab/ostoy-frontend:1.4.0 image-registry.openshift-image-registry.svc:5000/$OCP_PROJECT/ostoy-frontend:1.4.0
podman push image-registry.openshift-image-registry.svc:5000/$OCP_PROJECT/ostoy-frontend:1.4.0

echo $REGISTRY_HOST/$OCP_PROJECT/ostoy-frontend:1.4.0
docker push $REGISTRY_HOST/$OCP_PROJECT/ostoy-frontend:1.4.0

oc new-app $OCP_PROJECT/ostoy-frontend:1.4.0 --name=ostoy-frontend