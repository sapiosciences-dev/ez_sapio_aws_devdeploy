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

# Need CSI driver after all, but only for the EKS managed node group NOT auto
resource "aws_iam_role" "ebs_csi_controller" {
  name = "${module.eks.cluster_name}-ebs-csi-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Federated = module.eks.oidc_provider_arn }, # from your EKS module
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          # OIDC issuer host without https:// + SA subject
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi_controller.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi_driver_classic" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  # Bind IRSA role for the controller SA
  service_account_role_arn = aws_iam_role.ebs_csi_controller.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # Make the DS run only on your managed nodes (not on Auto Mode)
  configuration_values = jsonencode({
    controller = {
      # optional: keep controller off auto nodes too
      nodeSelector = { "sapio/pool" = "sapio-bls" }
    }
    node = {
      nodeSelector = { "sapio/pool" = "sapio-bls" }
    }
  })
}

# Create Sapio BLS volumes using custom driver accessible volume claims rather than auto mode volume claims.
resource "kubernetes_storage_class" "custom_gp3" {
  metadata {
    name = "custom-storage-class"
  }

  # *** This setting specifies the EKS Auto Mode provisioner ***
  storage_provisioner = "ebs.csi.aws.com"

  # The reclaim policy for a PersistentVolume tells the cluster
  # what to do with the volume after it has been released of its claim
  reclaim_policy = "Delete"

  # Delay the binding and provisioning of a PersistentVolume until a Pod
  # using the PersistentVolumeClaim is created
  volume_binding_mode = "WaitForFirstConsumer"

  # see StorageClass Parameters Reference here:
  # https://docs.aws.amazon.com/eks/latest/userguide/create-storage-class.html
  parameters = {
    type      = "gp3"
    encrypted = "true"
    iops     = "3000"
    throughput = "125"
  }

  # Give time for the cluster to complete (controllers, RBAC and IAM propagation)
  # See https://github.com/setheliot/eks_auto_mode/blob/main/docs/separate_configs.md
  depends_on = [aws_eks_addon.ebs_csi_driver_classic]
}

#
# EBS (Kubernetes) Persistent Volume Claim
resource "kubernetes_persistent_volume_claim_v1" "sapio_ebs_pvc" {
  metadata {
    name = local.ebs_sapio_app_data_claim_name
    namespace = local.sapio_ns
  }

  spec {
    # Volume can be mounted as read-write by a single node
    #
    # ReadWriteOnce access mode should enable multiple pods to
    # access it when the pods are running on the same node.
    #
    # Using EKS Auto Mode it appears to only allow one pod to access it
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = var.bls_server_storage_size
      }
    }

    storage_class_name = kubernetes_storage_class.custom_gp3.metadata[0].name
  }

  # Setting this allows `Terraform apply` to continue
  # Otherwise it would hang here waiting for claim to bind to a pod
  wait_until_bound = false

  # Give time for the cluster to complete (controllers, RBAC and IAM propagation)
  # See https://github.com/setheliot/eks_auto_mode/blob/main/docs/separate_configs.md
  depends_on = [kubernetes_storage_class.custom_gp3]
}