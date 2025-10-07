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

  # Pull the first number (integer or decimal) from the string, e.g. "20Gi" -> "20", "20.5GB" -> "20.5"
  _size_matches     = regexall("\\d+(?:\\.\\d+)?", var.bls_server_temp_storage_size)
  bls_temp_gib_raw  = length(local._size_matches) > 0 ? tonumber(local._size_matches[0]) : 0
  bls_temp_gib_int  = ceil(local.bls_temp_gib_raw)
  node_root_gib = local.bls_temp_gib_int + 20
}

module "vpc" {

  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "${local.prefix_env}-sapioeks-vpc"
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
  version = "~> 21.0"   # latest 20.x

  timeouts = {
    delete = "120m"
    create = "120m"
  }
  addons_timeouts = {
    delete = "120m"
    create = "120m"
  }

  name    = local.cluster_name
  kubernetes_version = local.cluster_version

  endpoint_public_access  = true
  endpoint_private_access = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # *** AWS EKS Auto Mode is enabled here ***
  # Auto compute, storage, and load balancing are enabled here
  # This replaces the more complex eks_managed_node_groups block
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  # Cluster access entry
  enable_cluster_creator_admin_permissions = true

  # --- SELF-MANAGED NODE GROUP (disruption-averse) ---
  # This ASG is NOT managed by Auto Mode, so no 21-day rotation.
  eks_managed_node_groups = {
    sapio_bls = {
      node_group_name = "sapio-bls"
      name       = "sapio-bls"
      subnet_ids = module.vpc.private_subnets

      node_repair_config = {
        enabled = true
      }

      # Pin capacity to avoid any scale-in/scale-out churn
      min_size     = 1
      max_size     = 1
      desired_size = 1

      # Use On-Demand capacity and a single instance type
      instance_types = [var.sapio_bls_instance_type]
      capacity_type = "ON_DEMAND"
      disk_size = local.node_root_gib

      # Use latest EKS-optimized AL2023 AMI (x86_64)
      ami_type = "AL2023_x86_64_STANDARD"

      # Protect new instances from scale-in so the ASG won't pick them
      # for termination during any scale-in or health churn
      asg_new_instances_protected_from_scale_in = true

      # Keep this group's desired size under your control (no instance refresh)
      enable_instance_refresh = false

      labels = {
        "sapio/pool"                     = "sapio-bls"
      }


      update_config = {
        max_unavailable = 1
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"        # IMDSv2
        http_put_response_hop_limit = 2                 # **key change**
        instance_metadata_tags      = "enabled"
      }
    }
  }

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
    from_port       = 8443
    to_port         = 8443
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
    description = "Allow Debug" # Note: Debug is not serviced to Sapio BLS by default.
    from_port   = 5005
    to_port     = 5005
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    security_groups = [local.publish_security_group]
  }
  ingress {
    description = "Allow SSH" # Note: SSH isn't serviced to Sapio BLS by default.
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



# Namespace creations
locals{
  analytic_server_ns = "sapio-analytic-server"
  sapio_ns = "sapio"
  es_namespace             = "elasticsearch"
}
resource "kubernetes_namespace" "sapio_analytic_server" {
  metadata {
    name = local.analytic_server_ns
  }
  depends_on = [module.eks]
}
resource "kubernetes_namespace" "sapio" {
  metadata {
    name = local.sapio_ns
  }
  depends_on = [module.eks]
}
resource "kubernetes_namespace" "elasticsearch" {
  metadata {
    name = local.es_namespace
  }
  depends_on = [module.eks]
  timeouts {
    delete = "30m"
  }
}
