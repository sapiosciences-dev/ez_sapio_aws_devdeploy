###############
#
# Self-Managed EKS Addons.
#
# Logical order: 02
##### "Logical order" refers to the order a human would think of these executions
##### (although Terraform will determine actual order executed)
#
# These addons are needed for minimum connectivity with the self-managed node that Sapio BLS runs on which
# we can't shutdown the node without terminating service to end users.

# ID Agent
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name      = module.eks.cluster_name
  addon_name        = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

# VPC CNI
resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = module.eks.cluster_name
  addon_name        = "vpc-cni"
  # Pin one that’s supported for your K8s minor; example only:
  # You can also omit addon_version to let AWS pick the latest compatible.
  # addon_version  = "v1.18.4-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # Optional: tweak density/behavior via supported envs
  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"  # higher pod density on Nitro
      WARM_IP_TARGET           = "1"
      WARM_ENI_TARGET          = "0"
      # ENABLE_POD_ENI         = "true"  # only if you plan SG-for-Pods
    }
  })
  depends_on = [aws_eks_addon.pod_identity_agent]
}

# kube-proxy (managed by EKS, but good to pin/ensure present)
resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = module.eks.cluster_name
  addon_name        = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on = [aws_eks_addon.pod_identity_agent]
}

# CoreDNS
resource "aws_eks_addon" "coredns" {
  cluster_name      = module.eks.cluster_name
  addon_name        = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on = [aws_eks_addon.pod_identity_agent]
}

# Create an IAM role the CNI will use
module "cni_pod_identity_role" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4"

  name                 = "${module.eks.cluster_name}-cni"
  attach_aws_vpc_cni_policy    = true  # attaches AmazonEKS_CNI_Policy
  aws_vpc_cni_enable_ipv4   = true
}

# Associate that role with the aws-node SA in kube-system
resource "aws_eks_pod_identity_association" "cni" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = module.cni_pod_identity_role.iam_role_arn
}