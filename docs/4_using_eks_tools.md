# Diagnostic: Using EKS Tools

All of these should be done within the disposable Admin EC2.

## Login to AWS EKS
```shell
aws eks update-kubeconfig --region <aws-region> --name <aws-cluster-name>
```
This will get your EKS configuration to set up to ekssapio-dev-cluster.
To find the cluster name, go to your region's AWS console and go to EKS.
The Cluster name should be the title of each cluster in the clusters table.

## Check Node Status
```shell
kubectl get nodes
```
This command will list all the pods in the default namespace.


## Check HELM Status
```shell
helm list -n <namespace>
```
This will let you look at helm chart for the provided namespace.

## Check Deployment Status
```shell
kubectl -n <namespace> get statefulsets,deploy,po,pvc,svc,events
```
This command will get all namespaced events. 
You will then be able to see deployment error logs in the namespace.

```shell
kubectl -n <namespace> get events --sort-by='.lastTimestamp'
```
This command will sort the events by time.

## Check Pod Status
```shell
kubectl logs <pod-name> -n <namespace>
```
This command will get the logs for a specific pod in the namespace.
You may get the launch errors if it is waiting for a healthcheck but the healthcheck had failed.
For example it will show base64 key error during init if it was supplied incorrectly.
To get the list of pods, you can either directly use the UI AWS console, or use the command:
```shell
kubectl get pods -n <namespace>
```
To list all namespaces, use:
```shell
kubectl get namespaces
```
To get pod info, use:
```shell
kubectl describe pod <pod-name> -n <namespace>
```
You will get the exact pod configurations as well as the current status.

# Assigning Console View Permissions
After deployment, you may receive an error if you use the AWS console,
navigating to EKS Compute tab, and see a message about insufficient permissions.
This may be the case even if you have Amazon default admin permissions.

To resolve this issue, go to the EKS Access tab, add a new policy "AmazonEKSAdminViewPolicy" 
at cluster level to your IAM principal.

# Redeploy NEW elasticsearch and lose data
If you need to redeploy elasticsearch and lose all data, you can do the following:
```shell
helm delete elasticsearch -n elasticsearch
terraform destroy -target=helm_release.elasticsearch -var-file=environment/<env_filename>.tfvars
```
Then rerun the terraform deploy script.

You will have to rebuild the chem cartridge and elasticsearch state in Sapio app.
This generally should be unnecessary but can be useful in dev.

Note: we intentionally do not set "replace=true" in to terraform script, 
because the doc says it is unsafe to use in production.

# Obtaining Secret Values
You must have RBAC role permissions to read secrets from EKS in order to do this.
(You can also view them in AWS EKS Console, if you have access)

Use
```shell
kubectl -n <ns> get secret <secret-name> -o jsonpath='{.data}'
```
For example
```shell
# MySQL Root Passwords
kubectl -n sapio get secret mysql-root-user -o jsonpath='{.data}'
# Elasticsearch App User Passwords
kubectl -n sapio get secret es-app-user -o jsonpath='{.data}'
# Elasticsearch Certificate Status
kubectl -n elasticsearch get certificate es-http-cert -o yaml
```