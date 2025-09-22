# Diagnostic: Using EKS Tools
```shell
aws eks update-kubeconfig --region <aws-region> --name <aws-cluster-name>
```
This will get your EKS configuration to set up to ekssapio-dev-cluster.
To find the cluster name, go to your region's AWS console and go to EKS.
The Cluster name should be the title of each cluster in the clusters table.

```shell
kubectl get nodes
```
This command will list all the pods in the default namespace.

```shell
helm list -n <namespace>
```
This will let you look at helm chart for the provided namespace.

```shell
kubectl -n <namespace> get statefulsets,deploy,po,pvc,svc,events
```
This command will get all namespaced events. 
You will then be able to see deployment error logs in the namespace.

