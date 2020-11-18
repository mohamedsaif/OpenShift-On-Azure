# https://docs.openshift.com/container-platform/4.5/security/certificates/replacing-default-ingress-certificate.html

# Create new configuration for the custom root CA public key
oc create configmap custom-ca \
     --from-file=ca-bundle.crt=</path/to/example-ca.crt> \
     -n openshift-config

oc patch proxy/cluster \
     --type=merge \
     --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'

# Create a new TLS secret for a wildcard certificate for *.apps.CLUSTER-BASE-DOMAIN
oc create secret tls <secret> \
     --cert=</path/to/cert.crt> \
     --key=</path/to/cert.key> \
     -n openshift-ingress


oc patch ingresscontroller.operator default \
     --type=merge -p \
     '{"spec":{"defaultCertificate": {"name": "<secret>"}}}' \
     -n openshift-ingress-operator