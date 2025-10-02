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
      values   = ["system:serviceaccount:${local.analytic_server_ns}:${local.app_serviceaccount}",
      "system:serviceaccount:${local.sapio_ns}:${local.app_serviceaccount}",
      "system:serviceaccount:default:${local.app_serviceaccount}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc}:aud"
      values = ["sts.amazonaws.com"]
    }
  }

  depends_on = [kubernetes_namespace.elasticsearch, kubernetes_namespace.sapio, kubernetes_namespace.sapio_analytic_server]
}

### Analytic Server IRSA And Service Account ###
resource "aws_iam_role" "analytic_server_irsa" {
  name               = "as-${local.prefix_env}-irsa"
  assume_role_policy = data.aws_iam_policy_document.service_account_trust_policy.json
}

resource "kubernetes_service_account_v1" "analytic_server_account" {
  metadata {
    name      = local.analytic_serviceaccount
    namespace = local.analytic_server_ns
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.analytic_server_irsa.arn
    }
  }
  depends_on = [kubernetes_namespace.sapio_analytic_server]
}

### Sapio BLS IRSA And Service Account ###
resource "aws_iam_role" "app_irsa" {
  name               = "app-${local.prefix_env}-irsa"
  assume_role_policy = data.aws_iam_policy_document.service_account_trust_policy.json
}

# Attach S3 to EXISTING IRSA role, but only for the Sapio BLS IRSA not analytic server.
resource "aws_iam_role_policy_attachment" "app_irsa_bucket_access" {
  role       = aws_iam_role.app_irsa.name
  policy_arn = aws_iam_policy.bucket_policy.arn
}

resource "kubernetes_service_account_v1" "sapio_account" {
  metadata {
    name      = local.app_serviceaccount
    namespace = local.sapio_ns
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app_irsa.arn
    }
  }
  depends_on = [kubernetes_namespace.sapio, aws_iam_role_policy_attachment.app_irsa_bucket_access]
}

# Create a role to read "sapio" namespaced secret
resource "kubernetes_role" "sapio_secret_reader" {
  metadata {
    name      = "sapio-secret-reader"
    namespace = kubernetes_namespace.sapio.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list"]
  }
}

# Assign the sapio namespace reader role to sapio app service account, so Sapio BLS can read "sapio" namespaced secrets.
resource "kubernetes_role_binding" "sapio_secret_reader_binding" {
  metadata {
    name      = "sapio-secret-reader-binding"
    namespace = kubernetes_namespace.sapio.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.sapio_secret_reader.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.app_serviceaccount
    namespace = kubernetes_namespace.sapio.metadata[0].name
  }
}