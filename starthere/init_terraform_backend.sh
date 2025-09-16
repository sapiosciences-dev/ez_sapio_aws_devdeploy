#!/usr/bin/env bash
set -euo pipefail
# ONLY need to run this once.
# vars
REGION=us-east-1
BUCKET_NAME=terraform-state-bucket-eks-auto-sapio
LOCK_TABLE=terraform-lock

check_s3_bucket() {
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$BE_REGION" 2>/dev/null; then
      echo "❌ S3 bucket '$BUCKET_NAME' already exists."
      exit 1
    else
      echo "✅ S3 bucket '$BUCKET_NAME' does NOT exist."
    fi
}

check_dynamodb_table() {
    if aws dynamodb describe-table --table-name "$DDB_TABLE_NAME" --region "$BE_REGION" >/dev/null 2>&1; then
        echo "❌ DynamoDB table '$DDB_TABLE_NAME' already exists."
        exit 1
    else
        echo "✅ DynamoDB table '$DDB_TABLE_NAME' does NOT exist."
    fi
}

check_s3_bucket
check_dynamodb_table

# Create the bucket (omit LocationConstraint ONLY for us-east-1)
aws s3api create-bucket --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  $( [ "$REGION" = "us-east-1" ] || echo --create-bucket-configuration LocationConstraint=$REGION )

# Hardening: versioning + default encryption + block public access
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration '{
    "BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true
  }'

# Create the DynamoDB lock table
aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo "✅ S3 bucket '$BUCKET_NAME' and DynamoDB table '$LOCK_TABLE' have been created in region '$REGION'."