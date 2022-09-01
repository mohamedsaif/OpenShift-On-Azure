# Docs: https://docs.microsoft.com/en-us/azure/openshift/howto-create-a-storageclass

AZURE_FILES_RESOURCE_GROUP=$ARO_RG
LOCATION=westeurope

# az group create -l $LOCATION -n $AZURE_FILES_RESOURCE_GROUP

AZURE_STORAGE_ACCOUNT_NAME=aroweustoragemsft

az storage account create \
	--name $AZURE_STORAGE_ACCOUNT_NAME \
	--resource-group $AZURE_FILES_RESOURCE_GROUP \
	--kind StorageV2 \
	--sku Standard_LRS

ARO_RESOURCE_GROUP=$ARO_RG
ARO_CLUSTER=$CLUSTER
ARO_SERVICE_PRINCIPAL_ID=$(az aro show -g $ARO_RESOURCE_GROUP -n $ARO_CLUSTER --query servicePrincipalProfile.clientId -o tsv)
echo $ARO_SERVICE_PRINCIPAL_ID
AZURE_FILES_RESOURCE_GROUP_RES_ID=$(az group show -n $AZURE_FILES_RESOURCE_GROUP --query id -o tsv)
echo $AZURE_FILES_RESOURCE_GROUP_RES_ID
az role assignment create --role Contributor --scope $AZURE_FILES_RESOURCE_GROUP_RES_ID --assignee $ARO_SERVICE_PRINCIPAL_ID -g $AZURE_FILES_RESOURCE_GROUP

az role assignment list \
    --all \
    --assignee $ARO_SP_ID \
    --output json | jq '.[] | {"principalName":.principalName, "roleDefinitionName":.roleDefinitionName, "scope":.scope}'


ARO_API_SERVER=$(az aro list --query "[?contains(name,'$ARO_CLUSTER')].[apiserverProfile.url]" -o tsv)

oc login -u kubeadmin -p $(az aro list-credentials -g $ARO_RESOURCE_GROUP -n $ARO_CLUSTER --query=kubeadminPassword -o tsv) $ARO_API_SERVER

oc create clusterrole azure-secret-reader \
	--verb=create,get \
	--resource=secrets

oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder

cat << EOF >> azure-storageclass-azure-file.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: azure-file
provisioner: kubernetes.io/azure-file
parameters:
  location: $LOCATION
  secretNamespace: kube-system
  skuName: Standard_LRS
  storageAccount: $AZURE_STORAGE_ACCOUNT_NAME
  resourceGroup: $AZURE_FILES_RESOURCE_GROUP
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

oc create -f azure-storageclass-azure-file.yaml

# change default storage to Azure Files
oc patch storageclass managed-premium -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

oc patch storageclass azure-file -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# validate
oc new-project azfiletest
oc new-app httpd-example

#Wait for the pod to become Ready
curl $(oc get route httpd-example -n azfiletest -o jsonpath={.spec.host})

#If you have set the storage class by default, you can omit the --claim-class parameter
oc set volume dc/httpd-example --add --name=v1 -t pvc --claim-size=1G -m /data --claim-class='azure-file'

#Wait for the new deployment to rollout
export POD=$(oc get pods --field-selector=status.phase==Running -o jsonpath={.items[].metadata.name})
oc exec httpd-example-1-zp8dl -- bash -c "echo 'azure file storage $RANDOM' >> /data/test.txt"

oc exec httpd-example-1-zp8dl -- bash -c "cat /data/test.txt"

# validate 2
AZURE_FILES_SECRET=custom-azure-storage
AZURE_STORAGE_ACCOUNT_KEY=
AZURE_FILES_SHARE_NAME=aro-share
oc create secret generic $AZURE_FILES_SECRET --from-literal=azurestorageaccountname=$AZURE_STORAGE_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$AZURE_STORAGE_ACCOUNT_KEY 

cat << EOF >> azure-storage-pv.yaml
apiVersion: "v1"
kind: "PersistentVolume"
metadata:
  name: "pv0001" 
spec:
  capacity:
    storage: "5Gi" 
  accessModes:
    - "ReadWriteMany"
  storageClassName: azure-file
  azureFile:
    secretName: $AZURE_FILES_SECRET
    shareName: $AZURE_FILES_SHARE_NAME
    readOnly: false
EOF

oc apply -f azure-storage-pv.yaml

cat << EOF >> azure-storage-pvc.yaml
apiVersion: "v1"
kind: "PersistentVolumeClaim"
metadata:
  name: "claim1" 
spec:
  accessModes:
    - "ReadWriteMany"
  resources:
    requests:
      storage: "5Gi" 
  storageClassName: azure-file 
  volumeName: "pv0001"
EOF

oc apply -f azure-storage-pvc.yaml

export POD=pod-name
cat << EOF >> azure-storage-pvc-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: $POD 
spec:
  containers:
    - name: nginx
      image: nginx:1.17.4
      ports:
      - containerPort: 80
      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5
      resources:
          limits:
            memory: 500Mi
            cpu: 500m
          requests:
            memory: 100Mi
            cpu: 100m
      volumeMounts:
        - mountPath: "/data" 
          name: azure-file-share
  volumes:
    - name: azure-file-share
      persistentVolumeClaim:
        claimName: claim1
EOF

oc apply -f azure-storage-pvc-pod.yaml


oc exec $POD -- bash -c "echo '$POD: azure file storage $RANDOM' >> /data/test.txt"

oc exec $POD -- bash -c "cat /data/test.txt"