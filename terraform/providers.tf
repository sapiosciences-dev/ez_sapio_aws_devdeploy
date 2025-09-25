# AWS Provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
  }
  # There is a deployment bug with more recent versions of Terraform
  # See: https://github.com/hashicorp/terraform-provider-kubernetes/issues/2779
  required_version = "~> 1.11.4"
}
provider "aws" {
  region = var.aws_region
}


data "aws_caller_identity" "current" {}

locals {
  prefix     = "ekssapio"
  prefix_env = "${local.prefix}-${var.env_name}"

  cluster_name    = "${local.prefix_env}-cluster"
  cluster_version = var.eks_cluster_version

  aws_account = data.aws_caller_identity.current.account_id

  ebs_sapio_app_data_claim_name = "ebs-sapio-app-claim"
}

#
# Setup the Kubernetes provider
# Can only be configured after the EKS cluster is created


# Data provider for cluster auth
data "aws_eks_cluster_auth" "cluster_auth" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

# Kubernetes provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token = data.aws_eks_cluster_auth.cluster_auth.token
  load_config_file       = false
}
# Helm provider pointed at the same cluster
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = [
        "eks", "get-token",
        "--cluster-name", module.eks.cluster_name,
        "--region", var.aws_region
      ]
    }
  }
}