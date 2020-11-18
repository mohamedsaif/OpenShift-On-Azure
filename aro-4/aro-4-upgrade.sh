## Cluster upgrades

# Current version status
oc get clusterversion

# Detailed cluster version
oc get clusterversion -o json | jq

# Update channel status
oc get clusterversion -o json|jq ".items[0].spec"

# Modifying update channel:
# Manually through updating the channel value under the spec section will result in updated cluster settings
oc edit clusterversion

# Or through the patch command
oc patch clusterversion version \
     --type=merge -p \
     '{"spec":{"channel": "stable-4.6"}}'

# review cluster upgrade history
oc get clusterversion -o json|jq ".items[0].status.history"
# Get available upgrade
oc get clusterversion -o json|jq ".items[0].status.availableUpdates"

# Check the upgrade command options
oc adm upgrade -h

# to upgrade to latest
oc adm upgrade --to-latest=true 

# to upgrade to particular version
oc adm upgrade --to=<version>