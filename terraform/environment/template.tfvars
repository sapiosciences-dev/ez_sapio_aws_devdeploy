env_name            = "TEMPLATE"
app1_name = "sapio_limsandeln"
aws_region          = "us-east-1"
eks_cluster_version = "1.32"
sapio_bls_docker_image_name = "my-sapio-app" # The image published to ECR for Sapio BLS on YOUR ECR repo under same account. MUST EXIST BEFORE DEPLOYMENT.
sapio_bls_docker_image_tag = "latest" # The tag of the image published to ECR for Sapio BLS on YOUR ECR repo under same account. MUST EXIST BEFORE DEPLOYMENT.
sapio_server_license_data = "" # Base64 of file. If not present, license must be loaded onto /data volume or baked under /opt/sapiosciences of the image.