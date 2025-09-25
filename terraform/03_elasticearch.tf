
########################################
# Elasticsearch Node Group
# Logical Order: 03
########################################
# --- Generate a DB password ---
# WARNING: DO NOT CHANGE random_password SPECS INSIDE AFTER DEPLOYED TO ENV.
# YOU MAY KILL THE ELASTICSEARCH root with a new password and lose existing password.

resource "random_password" "sapio_elasticsearch" {
  length  = 32
  special = false
}

locals {
  es_release_name          = "elasticsearch"
  es_app_user              = "sapio_app"
  es_index_pattern         = "*"

  es_app_secret_name       = "es-app-user"
  es_app_secret_namespaces = toset([local.es_namespace, local.sapio_ns])
}

# ECK Operator, not elasticsearch.
resource "kubernetes_namespace" "elastic_system" {
  metadata { name = "elastic-system" }
}

resource "helm_release" "eck_operator" {
  name             = "eck-operator"
  repository       = "https://helm.elastic.co"
  chart            = "eck-operator"
  version          = "3.1.0"       # check doc/site for newer
  namespace        = kubernetes_namespace.elastic_system.metadata[0].name
  create_namespace = false
  wait             = true
}

# ECK creates TLS + the `elastic` user secret automatically for this CR
resource "kubectl_manifest" "elasticsearch_eck" {
  yaml_body = yamlencode({
    apiVersion = "elasticsearch.k8s.elastic.co/v1"
    kind       = "Elasticsearch"
    metadata   = {
      name      = local.es_release_name
      namespace = local.es_namespace
    }
    spec = {
      version  = var.es_version
      nodeSets = [
        {
          name  = "masters"
          count = var.es_num_desired_masters
          config = {
            "node.roles" = ["master"]
            "node.store.allow_mmap" = false
          }
          volumeClaimTemplates = [
            {
              metadata = { name = "elasticsearch-data" }
              spec = {
                storageClassName = kubernetes_storage_class.ebs_gp3.metadata[0].name
                accessModes      = ["ReadWriteOnce"]
                resources        = { requests = { storage = var.es_master_storage_size } }
              }
            }
          ]
          podTemplate = {
            spec = {
              nodeSelector = {
                "eks.amazonaws.com/compute-type" = "auto"
              }

              containers = [{
                name  = "elasticsearch"
                resources = {
                  requests = {
                    cpu                = var.es_cpu_request
                    memory             = var.es_memory_limit
                  }
                  limits = {
                    cpu = var.es_cpu_limit
                    memory = var.es_memory_limit
                  }
                }
              }]
            }
          }
        },
        {
          name  = "data"
          count = var.es_num_desired_datas
          config = {
            "node.roles" = ["data_hot", "ingest"]
            "node.store.allow_mmap" = false
          }
          volumeClaimTemplates = [
            {
              metadata = { name = "elasticsearch-data" }
              spec = {
                storageClassName = kubernetes_storage_class.ebs_gp3.metadata[0].name
                accessModes      = ["ReadWriteOnce"]
                resources        = { requests = { storage = var.es_data_storage_size } }
              }
            }
          ]
          podTemplate = {
            spec = {
              nodeSelector = {
                "eks.amazonaws.com/compute-type" = "auto"
              }

              containers = [{
                name  = "elasticsearch"
                resources = {
                  requests = {
                    cpu                = var.es_cpu_request
                    memory             = var.es_memory_limit
                  }
                  limits = {
                    cpu = var.es_cpu_limit
                    memory = var.es_memory_limit
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })

  depends_on = [helm_release.eck_operator, kubernetes_storage_class.ebs_gp3]
}



# Secret with desired app password (namespace "elasticsearch" and "sapio" so sapio app and bootstrap script that creates user below can both read it)
resource "kubernetes_secret_v1" "es_app_creds" {
  for_each = local.es_app_secret_namespaces

  metadata {
    name      = local.es_app_secret_name
    namespace = each.key
  }
  data = {
    username = local.es_app_user
    password = random_password.sapio_elasticsearch.result
  }
  type = "Opaque"
  depends_on = [kubernetes_namespace.sapio]
}

# Job that waits for ES to be ready, then creates role and user
resource "kubernetes_job_v1" "es_bootstrap_app_user" {
  metadata {
    name      = "es-bootstrap-app-user"
    namespace = local.es_namespace
  }
  spec {
    backoff_limit = 4
    template {
      metadata { labels = { job = "es-bootstrap-app-user" } }
      spec {
        restart_policy = "OnFailure"
        container {
          name    = "bootstrap"
          image   = "curlimages/curl:8.10.1"
          command = ["/bin/sh","-c"]
          args = [<<-SCRIPT
            set -euo pipefail
            ns="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
            base="https://$ES_SERVICE.$ns.svc:9200"

            auth_user="elastic:$(cat /elastic/elastic_pw)"
            app_user="$APP_USER"
            app_pw="$(cat /app/user_pw)"
            cacert="/ca/ca.crt"

            http() { curl -sS --fail --cacert "$cacert" -u "$auth_user" -H 'Content-Type: application/json' "$@"; }
            code() { curl -sS -o /dev/null -w "%%{http_code}" --cacert "$cacert" -u "$auth_user" -H 'Content-Type: application/json' "$@"; }

            # Wait for security endpoint
            for i in $(seq 1 120); do
              c="$(code -XGET "$base/_security/_authenticate")" || true
              [ "$c" = "200" ] && break
              sleep 5
            done
            [ "$c" = "200" ] || { echo "Elasticsearch not ready (code=$c)"; exit 1; }

            # Upsert role (uses ES_INDEX_PATTERN)
            http -XPUT "$base/_security/role/app_writer" -d "{
              \"cluster\": [\"monitor\"],
              \"indices\": [{
                \"names\": [\"$ES_INDEX_PATTERN\"],
                \"privileges\": [\"create_index\",\"write\",\"create\",\"index\",\"read\",\"view_index_metadata\"]
              }]
            }" >/dev/null

            # Create/Update user idempotently
            ucode="$(code -XGET "$base/_security/user/$app_user")" || true
            if [ "$ucode" = "200" ]; then
              http -XPUT "$base/_security/user/$app_user" -d '{"roles":["app_writer"]}' >/dev/null
            elif [ "$ucode" = "404" ]; then
              http -XPUT "$base/_security/user/$app_user" -d "{\"password\":\"$app_pw\",\"roles\":[\"app_writer\"]}" >/dev/null
            else
              echo "Unexpected user check ($ucode)"; exit 1
            fi

            echo "Bootstrap complete."
          SCRIPT
          ]

          # pass locals via env (so the script can use $VAR)
          env {
            name = "APP_USER"
            value = local.es_app_user
          }
          env {
            name = "ES_INDEX_PATTERN"
            value = local.es_index_pattern
          }
          env {
            name = "ES_SERVICE"
            value = "${local.es_release_name}-es-http"
          }

          volume_mount {
            name = "elastic-user"
            mount_path = "/elastic"
            read_only = true
          }
          volume_mount {
            name = "app-creds"
            mount_path = "/app"
            read_only = true
          }
          volume_mount {
            name = "http-ca"
            mount_path = "/ca"
            read_only = true
          }
        }

        # Secrets from ECK (names derived from the CR name)
        volume {
          name = "elastic-user"
          secret {
            secret_name = "${local.es_release_name}-es-elastic-user"
            items {
              key = "elastic"
              path = "elastic_pw"
            }
            optional    = true
          }
        }
        volume {
          name = "http-ca"
          secret {
            secret_name = "${local.es_release_name}-es-http-certs-public"
            items {
              key = "ca.crt"
              path = "ca.crt"
            }
            optional    = true
          }
        }

        # Your app password Secret that you manage (opaque, contains key "user_pw")
        volume {
          name = "app-creds"
          secret {
            secret_name = local.es_app_secret_name
            items {
              key = "user_pw"
              path = "user_pw"
            }
          }
        }
      }
    }
  }

  depends_on = [kubectl_manifest.elasticsearch_eck]
}

resource "kubernetes_network_policy_v1" "allow_sapio_to_es" {
  metadata {
    name      = "allow-sapio-to-es"
    namespace = local.es_namespace
  }
  spec {
    pod_selector {
      match_labels = {
        app = "elasticsearch-master"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_expressions {
            key      = "kubernetes.io/metadata.name"
            operator = "In"
            values   = [local.sapio_ns, local.analytic_server_ns]
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 9200
      }
    }
  }
  depends_on = [kubernetes_namespace.elasticsearch]
}

# Wait until the CA secret exists
resource "null_resource" "wait_for_es_ca" {
  triggers = {
    es_name = local.es_release_name
    ns      = local.es_namespace
  }
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      for i in $(seq 1 120); do
        if kubectl get secret ${local.es_release_name}-es-http-ca-internal -n ${local.es_namespace} >/dev/null 2>&1; then
          exit 0
        fi
        sleep 5
      done
      echo "Timed out waiting for ES CA secret"; exit 1
    EOT
  }
  depends_on = [kubectl_manifest.elasticsearch_eck]
}

data "kubernetes_secret" "es_http_ca" {
  metadata {
    name      = "${local.es_release_name}-es-http-certs-public"
    namespace = local.es_namespace
  }
  depends_on = [null_resource.wait_for_es_ca]
}

resource "kubernetes_secret_v1" "es_ca_for_sapio" {
  metadata {
    name = "es-ca"
    namespace = local.sapio_ns
  }
  type = "Opaque"
  data = { "ca.crt" = data.kubernetes_secret.es_http_ca.data["ca.crt"] }
}

resource "kubernetes_secret_v1" "es_ca_for_as" {
  metadata {
    name = "es-ca"
    namespace = local.analytic_server_ns
  }
  type = "Opaque"
  data = { "ca.crt" = data.kubernetes_secret.es_http_ca.data["ca.crt"] }
}