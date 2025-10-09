# Firewall
admin_cidr_blocks = ["127.0.0.1/32"] # Replace with your local desktop IPs. This is for ARBITRARY REMOTE EXECUTIONS and debugs.
user_cidr_blocks  = ["0.0.0.0/0"]  # Replace with your end-user IPs unless you want everyone be able to access the app without VPN.

# Docker Image Data Variables REPLACE ME!
sapio_bls_docker_image = "REPLACE_ME"
analytic_server_docker_image = "sapiosciences/sapio_analytics_server:25.9" # REPLACE_ME
sapio_server_license_data = "" # REPLACE_ME Base64 of file. If not present, license must be loaded onto /data volume or baked under /opt/sapiosciences of the image.

# Environment Specific Variables
env_name            = "yourusername_dev" # each developer user should have its own env, unless you are playing with a shared env.
app1_name           = "sapio_limsandeln" # [Account]_[App] in your license file for app 1.
aws_region          = "us-east-1"
eks_cluster_version = "1.34"

# Hardware Spec Under Environment.
## Elasticsearch Specs
es_version = "7.17.12" # Sapio may require a particular version.
es_num_desired_masters = 1
es_num_desired_datas     = 1
es_cpu_request         = "1"
es_cpu_limit           = "2"
es_memory_limit        = "14Gi"
es_master_storage_size       = "50Gi"
es_data_storage_size =  "50Gi"

## MySQL Specs
mysql_multi_az       = false
mysql_instance_class = "db.t4g.medium"
mysql_allocated_storage = 50
mysql_retention_period_days = 2
mysql_skip_final_snapshot = true

## Analytic Server
analytic_enabled = true
analytic_server_cpu_request = "4"
analytic_server_memory_request = "12Gi"
analytic_server_cpu_limit = "4"
analytic_server_memory_limit = "14Gi"
analytic_server_temp_storage_size = "100Gi"
analytic_server_min_replicas = 1
analytic_server_max_replicas = 1
analytic_server_target_cpu_utilization_percentage = 60
analytic_server_target_memory_utilization_percentage = 75

## Sapio BLS
# This is Java app so memory limit and request should be identical.
sapio_bls_instance_type = "m5.xlarge" #m5.xlarge has 16Gi memory, 4 vCPU. Adjust according to your load.
bls_server_cpu_request = "1"
bls_server_memory_request = "12Gi"
bls_server_cpu_limit = "3500m"
bls_server_memory_limit = "12Gi"
bls_server_storage_size = "30Gi"
bls_server_temp_storage_size = "10Gi"

# S3
s3_enable_versioning = true
s3_versioning_snapshot_days = 2