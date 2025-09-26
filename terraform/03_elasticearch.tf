
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
# YQ: It's imperfect to use kubectl_manifest which may have a timedout token. Might want to revisit this later turn it to custom HELM.
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
      http = {
        tls = {
          selfSignedCertificate = {
            subjectAltNames = [
              # cluster-internal service DNS variants (cover them all)
              { dns = "${local.es_release_name}-es-http" },
              { dns = "${local.es_release_name}-es-http.${local.es_namespace}" },
              { dns = "${local.es_release_name}-es-http.${local.es_namespace}.svc" },
              { dns = "${local.es_release_name}-es-http.${local.es_namespace}.svc.cluster.local" },

              # YQ: Elasticsearch is only need to be exposed internally in cluster for default OOB use cases.
              # If you expose via a Service of type=LoadBalancer with a cloud DNS name:
              # { dns = "a1234567890abcdef.us-east-1.elb.amazonaws.com" },

              # If you use an ingress/your own DNS:
              # { dns = "es.mycorp.example.com" }
            ]
          }
        }
      }
      nodeSets = [
        {
          name  = "masters"
          count = var.es_num_desired_masters
          config = {
            "node.roles" = ["master"]
            "node.store.allow_mmap" = false
            "http.bind_host"        = "0.0.0.0"
            "http.publish_host"     = "$${POD_IP}"
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
              terminationGracePeriodSeconds = 30
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
            "node.roles" = ["data_hot","data_content","ingest"]
            "node.store.allow_mmap" = false
            "http.bind_host"        = "0.0.0.0"
            "http.publish_host"     = "$${POD_IP}"
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
              terminationGracePeriodSeconds = 30
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

  depends_on = [helm_release.eck_operator, kubernetes_storage_class.ebs_gp3, kubernetes_namespace.elasticsearch]
  timeouts {
    create = "60m"
  }
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

# Job that waits for ES to be ready, then creates role and user
resource "kubernetes_job_v1" "es_bootstrap_app_user" {
  metadata {
    name      = "es-bootstrap-app-user"
    namespace = local.es_namespace
  }
  spec {
    backoff_limit = 4
    # backoff_limit = 0 # This line when debugging the job.
    template {
      metadata { labels = { job = "es-bootstrap-app-user" } }
      spec {
        dns_policy    = "ClusterFirst"
        # restart_policy = "Never" # This line when debugging the job.
        restart_policy = "OnFailure"
        node_selector = {
          "eks.amazonaws.com/compute-type" = "auto"
        }
        container {
          name    = "bootstrap"
          image   = "curlimages/curl:8.10.1"
          command = ["/bin/sh","-c"]
          args = [<<-SCRIPT
                  set -Eeuo pipefail
            # show each command as it runs
            set -x

            log() { printf '%s %s\n' "$(date -Iseconds)" "$*" >&2; }

            ns="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
            fqdn="$ES_SERVICE.$ns.svc.cluster.local"
            base="https://$fqdn:9200"

            auth_user="elastic:$(cat /elastic/elastic_pw)"
            app_user="$APP_USER"
            app_pw="$(cat /app/user_pw)"
            cacert="/ca/ca.crt"

            http() { curl -sS --fail --cacert "$cacert" -u "$auth_user" -H 'Content-Type: application/json' "$@"; }
            code() { curl -sS -o /dev/null -w "%%{http_code}" --cacert "$cacert" -u "$auth_user" -H 'Content-Type: application/json' "$@"; }

            log "Bootstrap starting in ns=$ns; target=$fqdn"

            # Quick DNS check so we know WHY it fails if it does
            if command -v getent >/dev/null 2>&1; then
              if ! getent hosts "$fqdn" >/dev/null 2>&1; then
                log "DNS not resolved for $fqdn yet"
              else
                log "DNS resolved: $(getent hosts "$fqdn" | tr '\n' ' ')"
              fi
            fi

            # Wait for security endpoint; print the HTTP code every attempt
            tries=120
            c=""
            i=0
            while [ $i -lt $tries ]; do
              i=$((i+1))
              c="$(code -XGET "$base/_security/_authenticate" || true)"
              log "Probe $i/$tries -> /_security/_authenticate returned HTTP $c"
              [ "$c" = "200" ] && break
              sleep 5
            done
            if [ "$c" != "200" ]; then
              log "Elasticsearch not ready after $tries attempts (last code=$c)"
              # One last attempt to print body for debugging
              curl -sk --cacert "$cacert" -u "$auth_user" "$base" || true
              exit 1
            fi

            log "Upserting role app_writer (index pattern: $ES_INDEX_PATTERN)"
            http -XPUT "$base/_security/role/app_writer" -d '{
              "cluster": ["monitor"],
              "indices": [{
                "names": ["'"$ES_INDEX_PATTERN"'"],
                "privileges": ["create_index","write","create","index","read","view_index_metadata"]
              }]
            }' >/dev/stdout 2>&1 || { log "Failed to upsert role"; exit 1; }

            log "Checking user $app_user"
            ucode="$(code -XGET "$base/_security/user/$app_user" || true)"
            log "User lookup returned HTTP $ucode"

            if [ "$ucode" = "200" ]; then
              log "User exists; updating roles"
              http -XPUT "$base/_security/user/$app_user" -d '{"roles":["app_writer"]}' >/dev/stdout 2>&1 \
                || { log "Failed to update user roles"; exit 1; }
            elif [ "$ucode" = "404" ]; then
              log "User not found; creating"
              http -XPUT "$base/_security/user/$app_user" -d '{"password":"'"$app_pw"'","roles":["app_writer"]}' >/dev/stdout 2>&1 \
                || { log "Failed to create user"; exit 1; }
            else
              log "Unexpected user check HTTP $ucode"
              exit 1
            fi

            log "Bootstrap complete."
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
              key = "password"
              path = "user_pw"
            }
          }
        }
      }
    }
  }

  depends_on = [kubectl_manifest.elasticsearch_eck, null_resource.wait_for_es_ca]
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