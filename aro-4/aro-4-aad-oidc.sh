PREFIX=aro4
LOCATION=southafricanorth # Check the available regions on the ARO roadmap https://aka.ms/aro/roadmap
LOCATION_CODE=zan
CLUSTER=$PREFIX-$LOCATION_CODE
ARO_RG="$PREFIX-$LOCATION_CODE"

domain=$(az aro show -g $ARO_RG -n $CLUSTER --query clusterProfile.domain -o tsv)
location=$(az aro show -g $ARO_RG -n $CLUSTER --query location -o tsv)

# OC login details
CLUSTER_URL=$(az aro show -g $ARO_RG -n $CLUSTER --query apiserverProfile.url -o tsv)
USER=$(az aro list-credentials -g $ARO_RG -n $CLUSTER --query kubeadminUsername -o tsv)
PASSWORD=$(az aro list-credentials -g $ARO_RG -n $CLUSTER --query kubeadminPassword -o tsv)

webConsole=$(az aro show -g $ARO_RG -n $CLUSTER --query consoleProfile.url -o tsv)
oauthCallbackURL=https://oauth-openshift.apps.$domain.$location.aroapp.io/oauth2callback/AAD

CLIENT_SECRET=P@a$$w0rd$RANDOM
APP_ID=$(az ad app create \
  --query appId -o tsv \
  --display-name aro-auth \
  --reply-urls $oauthCallbackURL \
  --password $CLIENT_SECRET)

echo $APP_ID

TENANT_ID=$(az account show --query tenantId -o tsv)
echo $TENANT_ID

# configure OpenShift to use the email claim and fall back to upn to set the Preferred Username by adding the upn as part of the ID token returned by Azure Active Directory.
cat > manifest.json<< EOF
[{
  "name": "upn",
  "source": null,
  "essential": false,
  "additionalProperties": []
},
{
"name": "email",
  "source": null,
  "essential": false,
  "additionalProperties": []
},
{
  "name": "name",
  "source": null,
  "essential": false,
  "additionalProperties": []
}]
EOF

az ad app update \
  --set optionalClaims.idToken=@manifest.json \
  --id $APP_ID

# Add permission for the Azure Active Directory Graph.User.Read scope to enable sign in and read user profile.
az ad app permission add \
 --api 00000002-0000-0000-c000-000000000000 \
 --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope \
 --id $APP_ID

oc login $CLUSTER_URL --username=$USER --password=$PASSWORD

oc create secret generic openid-client-secret-azuread \
  --namespace openshift-config \
  --from-literal=clientSecret=$CLIENT_SECRET

# Replace ${APP_ID} and ${TENANT_ID} with relevant values
cat > oidc.yaml<< EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: AAD
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: ${APP_ID}
      clientSecret: 
        name: openid-client-secret-azuread
      extraScopes: 
      - email
      - profile
      extraAuthorizeParameters: 
        include_granted_scopes: "true"
      claims:
        preferredUsername: 
        - email
        - upn
        name: 
        - name
        email: 
        - email
      issuer: https://login.microsoftonline.com/${TENANT_ID}
EOF

oc apply -f oidc.yaml
# oauth.config.openshift.io/cluster configured

# Open a new private or ingonito window in your borswer and navigate the the console. Select AAD as your authentication and sign in with your AAD account
# Head back to the OC, to grant this user a cluster-admin role
oc get users
# Copy the name of the user
oc adm policy add-cluster-role-to-user cluster-admin $USER_NAME
# Refresh your browser you should see the privileges already took effect.

# Adding role to a user scoped at project
oc adm policy add-role-to-user <role> <user> -n <project>