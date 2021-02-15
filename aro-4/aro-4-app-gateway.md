# Exposing ARO via App Gateway

When you create a fully private cluster (both ingress and API), you can't reach this cluster via any client that don't have line-of-sight to the private IPs for the cluster vnet.

If you want to allow this cluster access via public internet, you can use Azure Application Gateway.

App Gateway can have both public and private front end IPs at the same time which give you the flexibility to decide how each component is exposed.

Now there are few notes that you would consider before applying this approach:

1. Public DNS: If you want to use a private cluster over public internet, you need to:

    - Select a cluster DNS name that can be resolved both publicly (to public IP) and privately (to private IP).
    - TLS Certificates: If you are relying on cluster self-signed certificates, you need to have in hand OpenShift root certificate, *.apps certificate and api certificate

2. Create new application gateway that has access to cluster network
    - Create application gateway in the same vnet (but in a new dedicated subnet)
    - Or create application gateway in peered hub vnet

