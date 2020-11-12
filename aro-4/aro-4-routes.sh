# ARO is created with a default ingress route
oc -n openshift-ingress-operator get ingresscontroller

# Details of the ingress router
oc -n openshift-ingress-operator get ingresscontroller/default -o json | jq '.spec'

# To check if this router has public or private external IP
oc -n openshift-ingress get svc

# OCP docs: https://docs.openshift.com/container-platform/4.3/networking/ingress-operator.html#nw-ingress-view_configuring-ingress

# It is good to look at the yaml definition of the default ingress:
oc -n openshift-ingress-operator get ingresscontroller/default -o yaml

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
oc -n openshift-ingress get svc

# creating a new project to use that ingress
oc new-project internal
# label the project with type=internal
oc label namespace/internal type=internal

# create new pod
oc new-app --docker-image erjosito/sqlapi:0.1

# expose the pod
oc expose svc sqlapi

# checking the route
oc describe route/sqlapi

# You will notice that the service is exposed over both default and internal as default don't have any selectors setup
# Let's add label to default route
oc -n openshift-ingress-operator edit ingresscontroller/default

# Add the following to the route spec:
# spec:
#   defaultCertificate:
#     name: 1997c2c5-965a-45cb-b11c-8e26e5a96882-ingress
#   namespaceSelector:
#     matchLabels:
#       type: external
#   replicas: 2

# to update the route, we will delete it to