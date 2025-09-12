env_name            = "production"
app1_name = "sapio_limsandeln"
aws_region          = "us-east-1"
eks_cluster_version = "1.32"
sapio_server_license_data = "" # Base64 of file. If not present, license must be loaded onto /data volume or baked under /opt/sapiosciences of the image.