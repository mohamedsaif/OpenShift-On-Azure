## Cluster upgrades

# Current version status
oc get clusterversion

# Detailed cluster version
oc get clusterversion -o json | jq

# Update channel status
oc get clusterversion -o json|jq ".items[0].spec"
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

# Modifying update channel
oc edit clusterversion
# Update the channel value under the spec section will result in updated cluster settings