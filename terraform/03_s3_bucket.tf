########################################
# S3 Bucket for Cluster
# Logical Order: 03
########################################

# If you're using terraform-aws-modules/eks, this output exists:
# module.eks.cluster_oidc_issuer_url  (e.g., "https://oidc.eks.us-east-1.amazonaws.com/id/XXXX")
data "aws_iam_openid_connect_provider" "this" {
  url = module.eks.cluster_oidc_issuer_url
}

locals {
  # Ensure global uniqueness while still "using local.cluster_name"
  s3_bucket_name = "${local.cluster_name}-${data.aws_caller_identity.current.account_id}"
  # The string Amazon uses in trust policy conditions (issuer host/path w/o https://)
  oidc_provider = replace(data.aws_iam_openid_connect_provider.this.url, "https://", "")
}

############################
# S3 bucket
############################

resource "aws_s3_bucket" "cluster_bucket" {
  bucket = local.s3_bucket_name

  tags = {
    Name        = local.s3_bucket_name
    ClusterName = local.cluster_name
  }
}

# By default S3 buckets created are publicly accessible. We do not want this.
resource "aws_s3_bucket_public_access_block" "cluster_bucket" {
  bucket                  = aws_s3_bucket.cluster_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################
# Bucket policy limited to this bucket
############################

data "aws_iam_policy_document" "bucket_full_access" {
  statement {
    sid     = "BucketLevelAccess"
    actions = [
      # bucket-level
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListBucketVersions"
    ]
    resources = [
      aws_s3_bucket.cluster_bucket.arn
    ]
  }

  statement {
    sid     = "ObjectLevelAccess"
    actions = [
      "s3:*Object*",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:PutObjectAcl",
      "s3:GetObjectAcl",
      "s3:PutObjectTagging",
      "s3:GetObjectTagging",
      "s3:ReplicateObject",
      "s3:RestoreObject"
    ]
    resources = [
      "${aws_s3_bucket.cluster_bucket.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "bucket_policy" {
  name        = "${local.cluster_name}-s3-fullaccess"
  description = "Full access to only the ${aws_s3_bucket.cluster_bucket.bucket} bucket and its objects"
  policy      = data.aws_iam_policy_document.bucket_full_access.json
}

############################
# Versioning (on/off via var)
############################

resource "aws_s3_bucket_versioning" "cluster_bucket" {
  provider = aws
  bucket   = aws_s3_bucket.cluster_bucket.id

  versioning_configuration {
    status = var.s3_enable_versioning ? "Enabled" : "Suspended"
  }
}

############################
# Lifecycle: expire old versions after N days (optional)
############################
# Only create the rule when:
#   - versioning is enabled, and
#   - versioning_snapshot_days > 0
#
# Note: aws_s3_bucket_lifecycle_configuration must be unique per bucket.
############################

resource "aws_s3_bucket_lifecycle_configuration" "cluster_bucket" {
  provider = aws
  bucket   = aws_s3_bucket.cluster_bucket.id

  # Ensure versioning is set first (AWS requires it for noncurrent rules)
  depends_on = [aws_s3_bucket_versioning.cluster_bucket]

  dynamic "rule" {
    for_each = var.s3_enable_versioning && var.s3_versioning_snapshot_days > 0 ? [1] : []
    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"
      filter {
        prefix = ""
      }

      noncurrent_version_expiration {
        noncurrent_days = var.s3_versioning_snapshot_days
      }
    }
  }

  # (Optional) Clean up stalled multipart uploads after 7 days
  rule {
    id     = "abort-incomplete-mpu"
    status = "Enabled"
    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

############################
# IRSA role for the specific ServiceAccount
############################

data "aws_iam_policy_document" "irsa_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      # Restrict to this exact service account
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.sapio_ns}:${local.app_serviceaccount}"]
    }

    # (Good practice) also require the audience
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa_role" {
  name               = "${local.cluster_name}-sa-${local.app_serviceaccount}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
}