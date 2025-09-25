# Firewall
admin_cidr_blocks = ["127.0.0.1/32"] # Replace with your local desktop IPs. This is for ARBITRARY REMOTE EXECUTIONS and debugs.
user_cidr_blocks  = ["0.0.0.0/0"]  # Replace with your end-user IPs unless you want everyone be able to access the app without VPN.

# Docker Image Data Variables REPLACE ME!
sapio_bls_docker_image = "REPLACE_ME"
analytic_server_docker_image = "sapiosciences/sapio_analytics_server:25.9" # REPLACE_ME
sapio_server_license_data = "" # REPLACE_ME Base64 of file. If not present, license must be loaded onto /data volume or baked under /opt/sapiosciences of the image.

# Environment Specific Variables
env_name            = "production"
app1_name           = "sapio_limsandeln" # [Account]_[App] in your license file for app 1.
aws_region          = "us-east-1"
eks_cluster_version = "1.33"

# Hardware Spec Under Environment.
## Elasticsearch Specs
es_version = "7.17.12" # Sapio may require a particular version.
es_num_desired_masters = 3
es_num_desired_datas     = 3
es_cpu_request         = "2"
es_cpu_limit           = "4"
es_memory_limit        = "62Gi"
es_master_storage_size       = "200Gi"
es_data_storage_size       = "500Gi"

## MySQL Specs
mysql_multi_az       = true
mysql_instance_class = "db.t4g.large"
mysql_allocated_storage = 500
mysql_retention_period_days = 14
mysql_skip_final_snapshot = false

## Analytic Server
analytic_enabled = true
analytic_server_cpu_request = "2"
analytic_server_memory_request = "24Gi"
analytic_server_cpu_limit = "8"
analytic_server_memory_limit = "48Gi"
analytic_server_temp_storage_size = "100Gi"
analytic_server_min_replicas = 1
analytic_server_max_replicas = 10
analytic_server_target_cpu_utilization_percentage = 60
analytic_server_target_memory_utilization_percentage = 70

## Sapio BLS
# This is Java app so memory limit and request should be identical.
sapio_bls_instance_type = "m5.2xlarge" #m5.2xlarge has 32Gi memory, 8 vCPU. Adjust according to your load.
bls_server_cpu_request = "4"
bls_server_memory_request = "28Gi"
bls_server_cpu_limit = "7500m"
bls_server_memory_limit = "28Gi"
bls_server_storage_size = "1000Gi"
bls_server_temp_storage_size = "100Gi"