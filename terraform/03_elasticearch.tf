
########################################
# Elasticsearch Node Group
# Logical Order: 03
########################################
# --- Generate a DB password ---
# WARNING: DO NOT CHANGE random_password SPECS INSIDE AFTER DEPLOYED TO ENV.
# YOU MAY KILL THE ELASTICSEARCH root with a new password and lose existing password.
resource "random_password" "es_root"{
  length = 32
  special = false
}

resource "random_password" "sapio_elasticsearch" {
  length  = 32
  special = false
}

locals {
  es_release_name          = "elasticsearch"
  es_app_user              = "sapio_app"
  es_index_pattern         = "*"
}

resource "kubernetes_job_v1" "wait_for_es_http_cert" {
  metadata {
    name      = "wait-for-es-http-cert"
    namespace = local.es_namespace
  }
  spec {
    backoff_limit = 0
    # ttl_seconds_after_finished = 300  # optional GC if your cluster supports it
    template {
      metadata { labels = { job = "wait-for-es-http-cert" } }
      spec {
        restart_policy = "OnFailure"

        container {
          name    = "gate"
          image   = "alpine:3.20"
          command = ["/bin/sh","-c"]
          args    = [<<-EOS
            set -euo pipefail
            # If this runs, the secret volume mounted => certificate secret exists.
            echo "es-http-tls mounted; listing contents:"
            ls -l /tls
            # sanity check (typical key for TLS secrets)
            test -s /tls/tls.crt
            echo "Certificate Ready. Proceeding."
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
            secret_name = "es-http-tls"  # created when Certificate becomes Ready
          }
        }
      }
    }
  }

  depends_on = [helm_release.cert_bootstrap]
}

# do not modify after deploy, chart drifts kills elasticsearch.
resource "helm_release" "elasticsearch" {
  name             = local.es_release_name
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  namespace        = local.es_namespace
  create_namespace = true
  version          = "8.5.1"

  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  reuse_values   = true # avoid chart drift.

  # Prefer fewer, more stable value injections:
  values = [yamlencode({
    # DEBUG ONLY, allow me to get into bash and find out what's wrong.
    livenessProbe = {
      initialDelaySeconds = 60000
      periodSeconds       = 20000
      timeoutSeconds      = 50000
      failureThreshold    = 10
    }
    readinessProbe = {
      initialDelaySeconds = 300000
      periodSeconds       = 100000
      timeoutSeconds      = 500000
      failureThreshold    = 12
    }

    replicas                  = var.es_num_desired_masters
    minimumMasterNodes        = var.es_num_min_masters
    resources = {
      requests = { cpu = var.es_cpu_request,  memory = var.es_memory_request }
      limits   = { cpu = var.es_cpu_limit,    memory = var.es_memory_limit }
    }
    volumeClaimTemplate = {
      storageClassName   = "ebs-storage-class"
      resources = {
        requests = { storage = var.es_storage_size }
      }
    }
    esConfig = {
      "elasticsearch.yml" = <<-EOT
        node.store.allow_mmap: false
        xpack.security.enabled: true
        xpack.security.http.ssl.enabled: true
        xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/http-certs/tls.crt
        xpack.security.http.ssl.key: /usr/share/elasticsearch/config/http-certs/tls.key
        xpack.security.http.ssl.certificate_authorities:
          - /usr/share/elasticsearch/config/http-certs/ca.crt
      EOT
    }
    protocol = "https"
    secretMounts = [{
      name       = "http-certs"
      secretName = "es-http-tls"
      path       = "/usr/share/elasticsearch/config/http-certs"
    }]
    nodeSelector = {
      "eks.amazonaws.com/compute-type" = "auto"
    }
  })]

  # Put the secret into set_sensitive to avoid noisy diffs, avoid unnecessary chart drifts.
  set_sensitive = [{
    name  = "secret.password"
    value = random_password.es_root.result
  }]

  depends_on = [kubernetes_job_v1.wait_for_es_http_cert, module.eks, kubernetes_storage_class.ebs_gp3 ]
}

locals {
  es_app_secret_name       = "es-app-user"
  es_app_secret_namespaces = toset([local.es_namespace, local.sapio_ns])
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
resource "kubernetes_job_v1" "es_bootstrap_permissions" {
  metadata {
    name      = "es-bootstrap-perms"
    namespace = local.es_namespace
  }
  spec {
    backoff_limit = 4
    template {
      metadata { labels = { job = "es-bootstrap-perms" } }
      spec {
        node_selector = { "eks.amazonaws.com/compute-type" = "auto" }
        restart_policy = "OnFailure"

        container {
          name  = "bootstrap"
          image = "curlimages/curl:8.10.1"
          command = ["/bin/sh","-c"]
          args = [<<-SCRIPT
            set -euo pipefail
            svc="elasticsearch-master.${local.es_namespace}.svc"
            base="https://$svc:9200"
            auth_user="elastic:$(cat /elastic/elastic_pw)"
            app_user="${local.es_app_user}"
            cacert="/ca/ca.crt"

            curl_json() { # usage: METHOD URL [JSON]
              method="$1"; url="$2"; data="$3"
              if [ -n "$data" ]; then
                curl -sS --fail --cacert "$cacert" -u "$auth_user" \
                  -H 'Content-Type: application/json' -X "$method" "$url" -d "$data"
              else
                curl -sS --fail --cacert "$cacert" -u "$auth_user" \
                  -H 'Content-Type: application/json' -X "$method" "$url"
              fi
            }

            http_code() { # usage: METHOD URL
              curl -sS -o /dev/null -w "%http_code" --cacert "$cacert" \
                   -u "$auth_user" -H 'Content-Type: application/json' -X "$1" "$2"
            }

            # Wait for security to respond over HTTPS
            for i in $(seq 1 120); do
              code=$(http_code GET "$base/_security/_authenticate") || true
              [ "$code" = "200" ] && break
              sleep 5
            done
            [ "$code" = "200" ] || { echo "Elasticsearch not ready (code=$code)"; exit 1; }

            # Upsert role
            curl_json PUT "$base/_security/role/app_writer" '{
              "cluster": ["monitor"],
              "indices": [{
                "names": ["${local.es_index_pattern}"],
                "privileges": ["create_index","write","create","index","read","view_index_metadata"]
              }]
            }' >/dev/null

            # Create/Update user idempotently
            user_code=$(http_code GET "$base/_security/user/$app_user") || true
            if [ "$user_code" = "200" ]; then
              curl_json PUT "$base/_security/user/$app_user" '{"roles":["app_writer"]}' >/dev/null
            elif [ "$user_code" = "404" ]; then
              pw="$(cat /app/user_pw)"
              curl_json PUT "$base/_security/user/$app_user" "{\"password\":\"$pw\",\"roles\":[\"app_writer\"]}" >/dev/null
            else
              echo "Unexpected user check ($user_code). Letting backoff retry."
              exit 1
            fi

            echo "Bootstrap complete."
          SCRIPT
          ]

          volume_mount {
            name = "elastic-creds"
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

        # Elastic built-in credentials (elastic user)
        volume {
          name = "elastic-creds"
          secret {
            secret_name = "elasticsearch-master-credentials"
            items {
              key = "password"
              path = "elastic_pw"
            }
          }
        }

        # Your application user's password
        volume {
          name = "app-creds"
          secret {
            secret_name = local.es_app_secret_name
            items {
              key = "password"
              path = "user_pw"
            }
          }
        }

        # Mount the ES HTTP CA (reuse the same secret that the ES pods use for HTTP)
        volume {
          name = "http-ca"
          secret {
            secret_name = "es-http-tls"      # <- contains ca.crt
            items {
              key = "ca.crt"
              path = "ca.crt"
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.elasticsearch,
    kubernetes_namespace.elasticsearch,
    kubernetes_secret_v1.es_app_creds
  ]
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
          match_labels = { kubernetes_io_metadata_name = "default" }
        }
        pod_selector {
          match_labels = {
            namespace = "sapio"
          } # matches your Deployment labels
        }
      }
      ports {
        protocol = "TCP"
        port     = 9200
      }
    }
  }
  depends_on = [helm_release.elasticsearch, kubernetes_namespace.elasticsearch]
}

