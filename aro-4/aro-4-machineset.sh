# Get the infra id of the deployment
INFRA_ID=$(oc get -o jsonpath='{.status.infrastructureName}{"\n"}' infrastructure cluster)
echo $INFRA_ID




