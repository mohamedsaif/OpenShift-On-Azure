# https://docs.openshift.com/container-platform/4.5/security/certificates/api-server.html

oc create secret tls <secret> \
     --cert=</path/to/cert.crt> \
     --key=</path/to/cert.key> \
     -n openshift-config

oc patch apiserver cluster \
     --type=merge -p \
     '{"spec":{"servingCerts": {"namedCertificates":
     [{"names": ["<FQDN>"], 
     "servingCertificate": {"name": "<secret>"}}]}}}' 

# Validate
oc get apiserver cluster -o yaml
