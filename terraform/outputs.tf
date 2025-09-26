# Output the VPC ID
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

# Output the EKS cluster details
output "eks_cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API Endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_arn" {
  description = "EKS Cluster ARN"
  value       = module.eks.cluster_arn
}

# Output the AWS Region
output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

# --- Outputs for Sapio BLS ---
locals {
  bls_lb_hostname = try(
    kubernetes_service_v1.sapio_bls_nlb.status[0].load_balancer[0].ingress[0].hostname,
    null
  )
  bls_lb_ip = try(
    kubernetes_service_v1.sapio_bls_nlb.status[0].load_balancer[0].ingress[0].ip,
    null
  )

  # Prefer hostname, then IP, else empty string
  bls_lb_host = coalesce(local.bls_lb_hostname, local.bls_lb_ip, "")
}

output "sapio_bls_external_url" {
  value = length(local.bls_lb_host) > 0 ? local.bls_lb_host : "Sapio BLS external endpoint is provisioning..."
}