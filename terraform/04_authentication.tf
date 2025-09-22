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
      variable = "${local.oidc}:sub"
      values   = ["system:serviceaccount:${local.analytic_server_ns}:${local.app_serviceaccount}",
      "system:serviceaccount:${local.sapio_ns}:${local.app_serviceaccount}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc}:aud"
      values = ["sts.amazonaws.com"]
    }
  },

  depends_on = [kubernetes_namespace.elasticsearch, kubernetes_namespace.sapio, kubernetes_namespace.sapio_analytic_server]
}

resource "aws_iam_role" "app_irsa" {
  name               = "app-${local.prefix_env}-irsa"
  assume_role_policy = data.aws_iam_policy_document.service_account_trust_policy.json
}

resource "kubernetes_service_account_v1" "analytic_server_account" {
  metadata {
    name      = local.app_serviceaccount
    namespace = local.analytic_server_ns
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app_irsa.arn
    }
  }
  depends_on = [kubernetes_namespace.sapio_analytic_server]
}

resource "kubernetes_service_account_v1" "sapio_account" {
  metadata {
    name      = local.app_serviceaccount
    namespace = local.sapio_ns
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app_irsa.arn
    }
  }
  depends_on = [kubernetes_namespace.sapio]
}