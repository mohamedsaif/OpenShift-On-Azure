# ARO is created with a default ingress route
oc -n openshift-ingress-operator get ingresscontroller

# Details of the default ingress router
oc -n openshift-ingress-operator get ingresscontroller/default -o json | jq '.spec'
# or
oc describe --namespace=openshift-ingress-operator ingresscontroller/default
# To check if this router has public or private external IP
oc -n openshift-ingress get svc

# OCP docs: https://docs.openshift.com/container-platform/4.3/networking/ingress-operator.html#nw-ingress-view_configuring-ingress

# It is good to look at the yaml definition of the default ingress:
oc -n openshift-ingress-operator get ingresscontroller/default -o json | jq

oc -n openshift-ingress-operator edit ingresscontroller/default

# The below yaml will create new internal ingress:
# apiVersion: operator.openshift.io/v1
# kind: IngressController
# metadata:
#   namespace: openshift-ingress-operator
#   name: internal
# spec:
#   domain: intapps.aro4-weu-14920.westeurope.aroapp.io
#   endpointPublishingStrategy:
#     type: LoadBalancerService
#     loadBalancer:
#       scope: Internal
#   namespaceSelector:
#     matchLabels:
#       type: internal

# namespaceSelector above is selected to instruct OCP to use specific namespace only. Other option is route selector
oc apply -f internal-ingress.yaml

# checking the newly created ingress:
oc -n openshift-ingress-operator get ingresscontroller
oc describe --namespace=openshift-ingress-operator ingresscontroller/internal-apps
oc -n openshift-ingress get svc

# creating a new project to use that ingress
oc new-project internal-db
# label the project with type=internal
oc label namespace/internal-db type=internal

# create new pod
oc new-app --docker-image erjosito/sqlapi:0.1
oc new-app --docker-image openshift/hello-openshift

# expose the pod
oc expose svc sqlapi
oc expose service/hello-openshift
# checking the route
oc describe route/sqlapi
oc describe route/hello-openshift
# You will notice that the service is exposed over both default and internal as default don't have any selectors setup
# Let's add label to default route
oc -n openshift-ingress-operator edit ingresscontroller/default
oc -n openshift-ingress-operator delete ingresscontroller/internal

# Add the following to the route spec:
# spec:
#   defaultCertificate:
#     name: 1997c2c5-965a-45cb-b11c-8e26e5a96882-ingress
#   namespaceSelector:
#     matchLabels:
#       type: external
#   replicas: 2

# to update the route, we will delete it to
nslookup hello-openshift-internal-db.apps.aro-weu.az.mohamedsaif.com
nslookup internal.apps.aro-weu.az.mohamedsaif.com
curl http://hello-openshift-internal-db.apps.aro-weu.az.mohamedsaif.com -k
curl http://hello-openshift-internal-db.internal.apps.aro-weu.az.mohamedsaif.com