# Make sure the you are signed in:
# oc login

# replace  azure_client_secret: <base64 value of customer new secret>
oc edit secrets azure-credentials -n kube-system

# replace base64 string with new values. It will require base64 decode -> modify -> base64 encode -> update secret
oc edit secret azure-cloud-provider -n kube-system

echo 'hello' | base64
echo 'aGVsbG8K' | base64 -d
