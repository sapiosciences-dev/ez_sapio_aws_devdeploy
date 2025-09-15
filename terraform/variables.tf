# Firewall
variable admin_cidr_blocks {
    description = "The CIDR blocks for admin access (e.g., SSH, RDP). Example: "
    type        = list(string)
    default     = ["127.0.0.1/32"]
}
variable user_cidr_blocks {
    description = "The CIDR block for end-user access (e.g., HTTP, HTTPS). Example: "
    type        = list(string)
    default     = ["0.0.0.0/0"]
}

# Define environment stage name
variable sapio_server_license_data {
  description = "The base64 string of the exemplar.license file granted for the AWS account ID of the terraform user."
  type        = string
}
variable sapio_bls_docker_image{
  description = "The docker image for the sapio bls server, published under your ecr e.g. my-sapio-app"
  type        = string
  nullable = false
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

# Hardware Specs
variable "es_num_desired_masters"{
  description = "Number of desired Elasticsearch master nodes"
  type        = number
  default     = 3
}
variable "es_num_min_masters"{
  description = "Minimum number of Elasticsearch master nodes"
  type        = number
  default     = 2
}
variable "es_cpu_request"{
  description = "CPU request for Elasticsearch master nodes"
  type        = string
  default     = "1"
}
variable "es_memory_request"{
  description = "Memory request for Elasticsearch master nodes"
  type        = string
  default     = "8Gi"
}
variable "es_cpu_limit" {
  description = "CPU limit for Elasticsearch master nodes"
  type        = string
  default     = "2"
}
variable "es_memory_limit" {
  description = "Memory limit for Elasticsearch master nodes"
  type        = string
  default     = "16Gi"
}
variable "es_storage_size" {
  description = "Storage size for Elasticsearch master nodes"
  type        = string
  default     = "100Gi"
}
# MySQL RDS variables
variable "mysql_multi_az" {
  description = "Whether to enable Multi-AZ for MySQL RDS instance"
  type        = bool
  default     = true
}
variable "mysql_instance_class" {
  description = "The instance class for MySQL RDS instance"
  type        = string
  default     = "db.t4g.large"
}
variable "mysql_allocated_storage" {
  description = "The allocated storage in GB for MySQL RDS instance"
  type        = number
  default     = 100
}
variable "mysql_retention_period_days" {
  description = "The retention period in days for MySQL RDS backups"
  type        = number
  default     = 14
}
variable "mysql_skip_final_snapshot" {
  description = "Whether to skip final snapshot on deletion for MySQL RDS instance"
  type        = bool
  default     = false
}
# Analytic Server
variable "analytic_server_cpu_request" {
  description = "CPU request for Analytic Server"
  type        = string
  default     = "2"
}
variable "analytic_server_memory_request" {
  description = "Memory request for Analytic Server"
  type        = string
  default     = "8Gi"
}
variable "analytic_server_cpu_limit" {
  description = "CPU limit for Analytic Server"
  type        = string
  default     = "4"
}
variable "analytic_server_memory_limit" {
  description = "Memory limit for Analytic Server"
  type        = string
  default     = "16Gi"
}
variable "analytic_server_temp_storage_size" {
  description = "Temporary Storage size for Analytic Server, used to store context data during analysis jobs."
  type        = string
  default     = "100Gi"
}
variable "analytic_server_min_replicas" {
  description = "Minimum number of replicas for Analytic Server"
  type        = number
  default     = 1
}
variable "analytic_server_max_replicas" {
  description = "Maximum number of replicas for Analytic Server"
  type        = number
  default     = 10
}
variable "analytic_server_target_cpu_utilization_percentage" {
  description = "Target CPU utilization percentage for Analytic Server autoscaling. Used by the Horizontal Pod Autoscaler to scale the number of replicas based on CPU usage."
  type        = number
  default     = 70
}
variable "analytic_server_target_memory_utilization_percentage" {
  description = "Target Memory utilization percentage for Analytic Server autoscaling Used by the Horizontal Pod Autoscaler to scale the number of replicas based on CPU usage."
  type        = number
  default     = 70
}
# BLS Server
variable "bls_server_cpu_request" {
  description = "CPU request for BLS Server"
  type        = string
  default     = "1"
}
variable "bls_server_memory_request" {
  description = "Memory request for BLS Server"
  type        = string
  default     = "4Gi"
}
variable "bls_server_cpu_limit" {
  description = "CPU limit for BLS Server"
  type        = string
  default     = "2"
}
variable "bls_server_memory_limit" {
  description = "Memory limit for BLS Server"
  type        = string
  default     = "8Gi"
}
variable "bls_server_storage_size" {
  description = "Storage size for BLS Server"
  type        = string
  default     = "50Gi"
}
variable "bls_server_temp_storage_size" {
  description = "Temporary storage size for BLS Server, used for file uploads and processing. Also used by PDF generation."
  type        = string
  default     = "20Gi"
}
