###############
#
# Resources needed to give the application the necessary permissions
# Includes IAM Role and Kubernetes ServiceAccount
#
# Logical order: 04
##### "Logical order" refers to the order a human would think of these executions
##### (although Terraform will determine actual order executed)
#

# AWS EKS Auto Mode does not seem to help with any of this
# (unless I am missing something)


#
# Use IRSA to give pods the necesssary permissions
#

#
# Create trust policy to be used by Service Account role


########################################
# IRSA trust policy
########################################

data "aws_iam_policy_document" "service_account_trust_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      identifiers = ["arn:aws:iam::${local.aws_account}:oidc-provider/${local.oidc}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc}:sub"
      values = ["system:serviceaccount:default:${local.app_serviceaccount}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc}:aud"
      values = ["sts.amazonaws.com"]
    }
  }
}