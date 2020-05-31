# NOTE: These steps assume that you have oc client tools already signed in into your ARO cluster

# DNS Forwarder setup (for on-premise DNS name resolutions)
oc edit dns.operator/default

# Update the spec: {} with your DNS forward setup
# spec:
#   servers:
#   - name: foo-server 
#     zones: 
#       - foo.com
#     forwardPlugin:
#       upstreams: 
#         - 1.1.1.1
#         - 2.2.2.2:5353
#   - name: bar-server
#     zones:
#       - bar.com
#       - example.com
#     forwardPlugin:
#       upstreams:
#         - 3.3.3.3
#         - 4.4.4.4:5454

# I used the following to forward to a DNS server deployed in a peered hub network
# spec:
#   servers:
#   - forwardPlugin:
#       upstreams:
#       - 10.165.5.4
#     name: azure-custom-dns
#     zones:
#     - mohamedsaif-cloud.corp

# Check the status
oc describe clusteroperators/dns

# Check the dns logs:
oc logs --namespace=openshift-dns-operator deployment/dns-operator -c dns-operator

# Test the DNS resolution
oc run --generator=run-pod/v1 -it --rm aro-ssh --image=debian
# Once you are in the interactive session, execute the following commands (replace the FQDN with yours)
apt-get update
apt-get install dnsutils -y
nslookup dns.mohamedsaif-cloud.corp.