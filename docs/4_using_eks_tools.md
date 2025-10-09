# Diagnostic: Using EKS Tools

All of these should be done within the disposable Admin EC2.

## Login to AWS EKS
```shell
aws eks update-kubeconfig --region <aws-region> --name <aws-cluster-name>
```

For Example:
```shell
aws eks update-kubeconfig --region us-east-1 --name ekssapio-dev-cluster
```

This will get your EKS configuration to set up to ekssapio-dev-cluster.
To find the cluster name, go to your region's AWS console and go to EKS.
The Cluster name should be the title of each cluster in the clusters table.

## Check Node Status
```shell
kubectl get nodes
```
This command will list all the pods in the default namespace.

## Update Sapio Analytic Deployment

To update Sapio BLS with new image:
1. Update the tagged version in your environmental file, if changed. You usually would want to have a different tag per deployment to keep track, but that is optional.
IF the tag had changed ,you must rerun deploy_cluster to update the environment deployment.
2. If the rollout update has not taken effect automatically, run the following command to immediately restart Sapio BLS deployment using newest image. This is required since even if the deployment has updated the containers won't immediately restart with new version.:

```shell
# If analytic server tag has changed:
kubectl rollout restart deployment ekssapio-dev-analyticserver-app-analytic-server-deployment -n sapio-analytic-server
# If sapio BLS tag has changed:
kubectl rollout restart deployment ekssapio-dev-sapio-app-deployment -n sapio
```


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
kubectl get events --sort-by='.lastTimestamp' -n <namespace>
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

# Force Destroy Pod
If you are trying to kill a EKS cluster and EKS cluster pod termination is failing, you can use:
```shell
 kubectl delete pod <pod_name> -n <namespace> --force --grace-period=0
```

Generally this command should only be used in devops when developing for custom deployment changes to pods.
The configuration will not be easily recovered.

# Tuning Rescale Policy for Analytic Server
Use the following command to see the logs as well as current metrics and the decisions made by horizontal autoscaler for Sapio Analytic Server deployment:

```shell
kubectl describe hpa ekssapio-stest-analyticserver-app-analytic-server-hpa -n sapio-analytic-server
```

First, confirm in log and in detailed status, that HPA is currently monitoring the analytic server successfully.
You would want to verify that there are no recent warnings about failures, and that "ScalingActive" has status true with reason as "ValidMetricFound".

Then you should read up the behavior and replica limits in the output, to make sure they sound reasonable and within your budget constraint for the deployment.

Load a large analytic batch workload to test. We in Sapio usually do this with a batch import of millions of compounds in an SDF file >250MB.

As the workload progresses, repeat this command as many times as needed when analytic server is in use, and see whether the scale up and scale down is acceptable as a user as the workload progresses in Sapio.

The following in an example output:

```text
ubuntu@ip-172-31-23-177:~/dev$ kubectl describe hpa ekssapio-stest-analyticserver-app-analytic-server-hpa -n sapio-analytic-server
Name:                                                     ekssapio-stest-analyticserver-app-analytic-server-hpa
Namespace:                                                sapio-analytic-server
Labels:                                                   <none>
Annotations:                                              <none>
CreationTimestamp:                                        Wed, 08 Oct 2025 22:40:33 +0000
Reference:                                                Deployment/ekssapio-stest-analyticserver-app-analytic-server-deployment
Metrics:                                                  ( current / target )
  resource cpu on pods  (as a percentage of request):     34% (699m) / 60%
  resource memory on pods  (as a percentage of request):  1% (389044Ki) / 70%
Min replicas:                                             1
Max replicas:                                             10
Behavior:
  Scale Up:
    Stabilization Window: 60 seconds
    Select Policy: Max
    Policies:
      - Type: Percent  Value: 100  Period: 60 seconds
  Scale Down:
    Stabilization Window: 300 seconds
    Select Policy: Min
    Policies:
      - Type: Percent  Value: 50  Period: 60 seconds
Deployment pods:       2 current / 2 desired
Conditions:
  Type            Status  Reason               Message
  ----            ------  ------               -------
  AbleToScale     True    ScaleDownStabilized  recent recommendations were higher than current one, applying the highest recent recommendation
  ScalingActive   True    ValidMetricFound     the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  False   DesiredWithinRange   the desired count is within the acceptable range
Events:
  Type     Reason                        Age                From                       Message
  ----     ------                        ----               ----                       -------
  Warning  FailedGetResourceMetric       51m                horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: unable to fetch metrics from resource metrics API: the server is currently unable to handle the request (get pods.metrics.k8s.io)
  Warning  FailedGetResourceMetric       51m                horizontal-pod-autoscaler  failed to get memory utilization: unable to get metrics for resource memory: unable to fetch metrics from resource metrics API: the server is currently unable to handle the request (get pods.metrics.k8s.io)
  Warning  FailedComputeMetricsReplicas  51m                horizontal-pod-autoscaler  invalid metrics (2 invalid out of 2), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: unable to fetch metrics from resource metrics API: the server is currently unable to handle the request (get pods.metrics.k8s.io)
  Warning  FailedGetResourceMetric       51m (x2 over 16h)  horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedGetResourceMetric       51m (x2 over 16h)  horizontal-pod-autoscaler  failed to get memory utilization: unable to get metrics for resource memory: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  51m (x2 over 16h)  horizontal-pod-autoscaler  invalid metrics (2 invalid out of 2), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             32m                horizontal-pod-autoscaler  New size: 2; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             31m                horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             21m                horizontal-pod-autoscaler  New size: 7; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             20m                horizontal-pod-autoscaler  New size: 8; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             17m                horizontal-pod-autoscaler  New size: 10; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             4m9s               horizontal-pod-autoscaler  New size: 5; reason: All metrics below target
  Normal   SuccessfulRescale             3m9s               horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             99s                horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
```

Note that when HPA computes number of desired replicas from average targets, the formula is:
```text
desired = ceil(currentReplicas * currentUtilization / targetUtilization)
```
So if we are currently at 2 replicas, and the current average utilization of pods is 100%, then the next desired replica number is:
```text
desired = ceil(2 * 100 / 60) = ceil(200 / 60) = ceil(3.3333...) = 4
```
This means if this is the stable average target in the current stabilisation window, the next scale up will change number of pods to 4, an increase of 2 pods in one scale-up.
But it cannot exceed the maximum scale up window within the defined period, which by default means it cannot exceed 100% of current size.

Let's try another example. If the current average utilization of pods is 80% and the target is 60%, and we currently have 2 replicas then
```text
desired = ceiling(2 * 80 / 60) = ceiling(2.667) = 3
```
This means after stabilization period expires, should the metric continue to hold, the next scale up will change the number of pods to 3, an increase of 1 pod in one scale-up.

With multiple targets (CPU and memory utilization), the desired # replica recommendation will use the maximum number of replicas across any metrics used the formula above.