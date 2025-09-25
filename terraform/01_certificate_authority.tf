###############
#
# AWS App Self-Signed Certificate Authority, and exporting the public certificate of CA to all namespaces.
#
# Logical order: 01
##### "Logical order" refers to the order a human would think of these executions
##### (although Terraform will determine actual order executed)
#
###############
locals {
  ca_target_namespaces = toset([local.sapio_ns, local.analytic_server_ns])
  ca_cm_name           = "es-ca"
}
## SELF SIGNING CERTIFICATE MANAGEMENT WITHIN THE CLUSTER
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.14.4"
  namespace        = local.cert_manager_ns
  create_namespace = true
  wait             = true
  atomic           = true          # roll back on failure
  cleanup_on_fail  = true
  set = [
    { name = "installCRDs", value = "true" },
    # --- Ensure it only resides in auto mode clusters.
    { name  = "nodeSelector.eks\\.amazonaws\\.com/compute-type", value = "auto" },
  ]
  depends_on = [module.eks, kubernetes_namespace.elasticsearch,
    kubernetes_namespace.sapio, kubernetes_namespace.sapio_analytic_server]
}

# install issuers + ES HTTP Certificate via local chart
resource "helm_release" "cert_bootstrap" {
  name       = "cert-bootstrap"
  chart      = "${path.module}/charts/cert-bootstrap"
  namespace  = local.cert_manager_ns
  wait       = true
  atomic           = true          # roll back on failure
  cleanup_on_fail  = true

  set = [
    { name = "esNamespace",      value = local.es_namespace },
    { name = "esHttpSecretName", value = "es-http-tls" },
    # elastic/elasticsearch chart’s HTTP Service is typically "<release>-master"
    { name = "esServiceName",    value = "${local.es_release_name}-master" },
    # --- Ensure it only resides in auto mode clusters.
    { name  = "nodeSelector.eks\\.amazonaws\\.com/compute-type", value = "auto" },
  ]

  depends_on = [helm_release.cert_manager]
}

# SA for CA transfer
resource "kubernetes_service_account_v1" "es_ca_sync" {
  metadata {
    name      = "es-ca-sync"
    namespace = local.es_namespace
  }
}


resource "kubernetes_role_binding_v1" "cm_write_binding" {
  for_each = local.ca_target_namespaces
  metadata {
    name      = "bind-edit-for-cm"
    namespace = each.key
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.es_ca_sync.metadata[0].name
    namespace = local.es_namespace
  }
}

# Final job.
resource "kubernetes_job_v1" "sync_es_ca_to_targets" {
  metadata {
    name      = "sync-es-ca-to-targets"
    namespace = local.es_namespace
  }
  spec {
    backoff_limit = 3
    template {
      metadata { labels = { job = "sync-es-ca-to-targets" } }
      spec {
        service_account_name = kubernetes_service_account_v1.es_ca_sync.metadata[0].name
        restart_policy       = "OnFailure"
        node_selector = {
          "eks.amazonaws.com/compute-type" = "auto"
        }

        container {
          name    = "sync"
          image   = "bitnami/kubectl:1.30"
          command = ["/bin/bash","-c"]
          args    = [<<-EOS
            set -Eeuo pipefail
            CERT=""
            if [ -s /tls/ca.crt ]; then CERT=/tls/ca.crt
            elif [ -s /tls/tls.crt ]; then CERT=/tls/tls.crt
            else echo "No ca.crt or tls.crt in /tls"; exit 1; fi

            for ns in ${local.sapio_ns} ${local.analytic_server_ns}; do
              echo "Syncing CA to $ns"
              kubectl -n "$ns" create configmap ${local.ca_cm_name} \
                --from-file=ca.crt="$CERT" \
                --dry-run=client -o yaml | kubectl -n "$ns" apply -f -
            done
            echo "Done."
          EOS
          ]
          volume_mount {
            name       = "es-tls"
            mount_path = "/tls"
            read_only  = true
          }
        }

        volume {
          name = "es-tls"
          secret {
            secret_name = "es-http-tls"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account_v1.es_ca_sync,
    kubernetes_role_binding_v1.cm_write_binding
  ]
}