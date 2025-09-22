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

To resolve this issue, go to the EKS Access tab, add a new policy "AmazonEKSViewPolicy" 
at cluster level to your IAM principal.