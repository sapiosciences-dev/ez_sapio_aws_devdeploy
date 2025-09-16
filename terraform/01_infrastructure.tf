###############
#
# AWS Infrastructure including the EKS Cluster
#
# Logical order: 01 
##### "Logical order" refers to the order a human would think of these executions
##### (although Terraform will determine actual order executed)
#
###############

#
# VPC and Subnets
data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  az_count = length(data.aws_availability_zones.available.names)
  max_azs  = min(local.az_count, 3) # Use up to 3 AZs, but only if available (looking at you, us-west-1 👀)
}

module "vpc" {

  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "${local.prefix_env}-vpc"
  cidr            = "10.0.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, local.max_azs)
  private_subnets = slice(["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"], 0, local.max_azs)
  public_subnets  = slice(["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"], 0, local.max_azs)

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Tag subnets for use by **Auto Mode** Load Balancer controller
  # https://docs.aws.amazon.com/eks/latest/userguide/tag-subnets-auto.html
  public_subnet_tags = {
    "Name"                   = "${local.prefix_env}-public-subnet"
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "Name"                            = "${local.prefix_env}-private-subnet"
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Terraform   = "true"
    Environment = local.prefix_env

    # Ensure workspace check logic runs before resources created
    always_zero = length(null_resource.check_workspace)
  }
}

#
# EKS Cluster using Auto Mode
module "eks" {

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"   # latest 20.x

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # *** AWS EKS Auto Mode is enabled here ***
  # Auto compute, storage, and load balancing are enabled here
  # This replaces the more complex eks_managed_node_groups block
  cluster_compute_config = {
    enabled    = true
    node_pools = ["memory-optimized"]
  }

  # Cluster access entry
  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"

    # Ensure workspace check logic runs before resources created
    always_zero = length(null_resource.check_workspace)
  }

  # Transient failures in creating StorageClass, PersistentVolumeClaim, 
  # ServiceAccount, Deployment, were observed due to RBAC propagation not 
  # completed. Therefore raising this from its default 30s 
  dataplane_wait_duration = "60s"

}

locals {
  publish_security_group = module.eks.node_security_group_id
}

# Create VPC endpoints (Private Links) for SSM Session Manager access to nodes
resource "aws_security_group" "vpc_endpoint_sg" {
  name   = "vpc-endpoint-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    description     = "Allow EKS Nodes to access VPC Endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [local.publish_security_group]
    cidr_blocks     = var.user_cidr_blocks
  }
  ingress {
    description = "healthcheck"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.user_cidr_blocks
    security_groups = [local.publish_security_group]
  }
  ingress {
    description = "Allow RMI"
    from_port   = 1099
    to_port     = 1099
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    security_groups = [local.publish_security_group]
  }
  ingress {
    description = "Allow Debug"
    from_port   = 5005
    to_port     = 5005
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    security_groups = [local.publish_security_group]
  }
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    security_groups = [local.publish_security_group]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }
}

resource "aws_vpc_endpoint" "private_link_ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }
}

resource "aws_vpc_endpoint" "private_link_ssmmessages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }
}

resource "aws_vpc_endpoint" "private_link_ec2messages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true

  tags = {
    Environment = local.prefix_env
    Terraform   = "true"
  }
}

## SELF SIGNING CERTIFICATE MANAGEMENT WITHIN THE CLUSTER
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.14.4"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    { name = "installCRDs", value = "true"}  # Required to install the CRDs
  ]
}

# A. Self-signed ClusterIssuer (bootstrap)
resource "kubernetes_manifest" "selfsigned_root" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = "selfsigned-root" }
    spec = {
      selfSigned = {}
    }
  }
  depends_on = [helm_release.cert_manager]
}

# B. Issue a CA certificate (isCA: true) in cert-manager ns
resource "kubernetes_manifest" "es_root_ca_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "es-root-ca"
      namespace = "cert-manager"
    }
    spec = {
      isCA       = true
      commonName = "es-root-ca"
      secretName = "es-root-ca"     # will contain tls.crt (CA) and tls.key
      privateKey = { algorithm = "RSA", size = 2048 }
      issuerRef  = { name = "selfsigned-root", kind = "ClusterIssuer" }
      duration    = "87600h"   # 10y
      renewBefore = "720h"     # 30d
    }
  }
  depends_on = [kubernetes_manifest.selfsigned_root]
}

# C. ClusterIssuer backed by that CA (cluster-wide signer)
resource "kubernetes_manifest" "es_ca_clusterissuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = "es-ca-issuer" }
    spec = {
      ca = { secretName = "es-root-ca" }  # secret must live in cert-manager namespace
    }
  }
  depends_on = [kubernetes_manifest.es_root_ca_cert]
}