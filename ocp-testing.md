# OCP Cluster Testing

Congratulations!

Now it is time to access the cluster mainly via OC client CLI.

>**NOTE:** Although it says completed, you might need to give it a few mins to warm up :)

I will be testing the cluster using OC client CLI.

```bash

# You can access the web-console as per the instructions provided, but let's try using oc CLI instead
cd ..
cd client

# this step so you will not need to use oc login (you might have a different path)
# export KUBECONFIG=~/ocp-installer/installer/installation/auth/kubeconfig

# basic operations
./oc version
./oc config view
./oc status

# Famous get pods
./oc get pod --all-namespaces

# Our cluster running a kubernetes and OpenShift services by default
./oc get svc
# NAME         TYPE           CLUSTER-IP   EXTERNAL-IP                            PORT(S)   AGE
# docker-registry ClusterIP   172.30.78.158
# kubernetes   ClusterIP      172.30.0.1   <none>                                 443/TCP   36m
# openshift    ExternalName   <none>       kubernetes.default.svc.cluster.local   <none>    24m

# No selected project for sure
./oc project

# if you are interested to look behind the scene on what is happing, access the logs
cat ./.openshift_install.log

```