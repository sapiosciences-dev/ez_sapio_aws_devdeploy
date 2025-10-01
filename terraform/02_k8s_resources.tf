###############
#
# Resources in the Kubernetes Cluster such as StorageClass
#
# Logical order: 02 
##### "Logical order" refers to the order a human would think of these executions
##### (although Terraform will determine actual order executed)
#
#
# EBS Storage Class

resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "ebs-storage-class"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  # *** This setting specifies the EKS Auto Mode provisioner ***
  storage_provisioner = "ebs.csi.eks.amazonaws.com"

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
  depends_on = [module.eks]
}

# SG with restricted inbound for NLB listeners
resource "aws_security_group" "sapio_nlb_frontend" {
  name   = "${local.prefix_env}-sapio-nlb-frontend"
  vpc_id = module.vpc.vpc_id

  ingress {
    description     = "Allow EKS Nodes to access VPC Endpoints"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    cidr_blocks     = var.user_cidr_blocks
  }
  ingress {
    description = "Allow Debug" # Note: Debug is not serviced to Sapio BLS by default.
    from_port   = 5005
    to_port     = 5005
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }
  ingress {
    description = "Allow RMI"
    from_port   = 1099
    to_port     = 1099
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }
}