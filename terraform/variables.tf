# Define environment stage name
variable sapio_server_license_data {
  description = "The base64 string of the exemplar.license file granted for the AWS account ID of the terraform user."
  type        = string
}
variable analytic_server_docker_image{
  description = "The docker image for the analytic server, e.g. sapiosciences/sapio_analytics_server:25.9"
  type        = string
  nullable = false
}
variable app1_name {
  description = "The app 1's account_app name, e.g. sapio_limsandeln if the account is sapio and the app is limsandeln. This should match app 1 of issued license."
  type        = string
  nullable = false
}

variable "env_name" {
  description = "Unique identifier for tfvars configuration used"
  type        = string
}

# AWS Region to deploy the EKS cluster
variable "aws_region" {
  description = "AWS region to deploy the EKS cluster"
  type        = string
  default     = "us-east-1"
}

# EKS version
variable "eks_cluster_version" {
  description = "EKS version"
  type        = string
  default     = "1.32"
}