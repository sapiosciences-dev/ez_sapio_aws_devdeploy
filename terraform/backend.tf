# Remote backend for storing Terraform state

# You need an S3 bucket and DynamoDB table in the same AWS account where you will deploy your resources
# These must be the in the AWS Region corresponding to the value below
# This can be a _different_ Region than where you deploy your resources
# You can change this Region below, as long as the S3 bucket and DDB table also go in that Region

# Update `bucket` below to the name of the S3 bucket you will use. This usually will be a new bucket
# but can also be one which you already use for Terraform state

# Create a DynamoDB table with the same name as the value of `dynamodb_table` below
# For this DynamoDB table, set LockID (type String) as the partition key (there is no Sort key)

terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-eks-auto-sapio"
    key            = "sapio-tf/${var.env_name}/terraform.tfstate"
    dynamodb_table = "terraform-lock"
    region         = var.aws_region
    encrypt        = true # For newbies: No customer managed key material for terraform state encryption. This uses S3 default encryption key.
    # kms_key_id     = "arn:aws:kms:REGION:ACCOUNT:key/XXXX-XXXX" # Optional, if you want to use custom KMS key for encryption
  }
}
