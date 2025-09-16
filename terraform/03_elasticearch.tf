
########################################
# Elasticsearch Node Group
# Logical Order: 03
########################################
# --- Generate a DB password ---
resource "random_password" "sapio_elasticsearch" {
  length  = 32
  special = true
}

locals {
  es_namespace             = "elasticsearch"
  es_release_name          = "elasticsearch"
  es_app_user              = "sapio_app"
  es_index_pattern         = "*"
}

resource "kubernetes_manifest" "es_http_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "es-http-cert"
      namespace = local.es_namespace
    }
    spec = {
      secretName  = "es-http-tls"           # <— same secret name your app already uses
      duration    = "2160h"                 # 90d
      renewBefore = "360h"                  # 15d
      privateKey  = { algorithm = "RSA", size = 2048 }
      usages      = ["digital signature","key encipherment","server auth"]
      issuerRef   = { name = "es-ca-issuer", kind = "ClusterIssuer" }
      dnsNames = [
        "elasticsearch-master.${local.es_namespace}.svc",
        "elasticsearch-master.${local.es_namespace}.svc.cluster.local"
      ]
    }
  }
  depends_on = [kubernetes_manifest.es_ca_clusterissuer]
}

resource "helm_release" "elasticsearch" {
  name             = local.es_release_name
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  namespace        = local.es_namespace
  create_namespace = true

  set = [
    { name = "replicas",                                  value = tostring(var.es_num_desired_masters) },
    { name = "minimumMasterNodes",                        value = tostring(var.es_num_min_masters) },
    { name = "esJavaOpts",                                value = "-Xms1g -Xmx1g" },

    { name = "resources.requests.cpu",                    value = var.es_cpu_request },
    { name = "resources.requests.memory",                 value = var.es_memory_request },
    { name = "resources.limits.cpu",                      value = var.es_cpu_limit },
    { name = "resources.limits.memory",                   value = var.es_memory_limit },

    # Persistent storage
    { name = "volumeClaimTemplate.storageClassName",      value = "gp3" },
    { name = "volumeClaimTemplate.resources.requests.storage", value = var.es_storage_size },

    # Avoid mmap unless you've set vm.max_map_count on nodes
    { name = "esConfig.elasticsearch\\.yml.node\\.store\\.allow_mmap", value = "false" },

    # HTTPS + mount certs from the secret created by cert-manager
    { name = "protocol",                                  value = "https" },
    { name = "secretMounts[0].name",                      value = "http-certs" },
    { name = "secretMounts[0].secretName",                value = "es-http-tls" },
    { name = "secretMounts[0].path",                      value = "/usr/share/elasticsearch/config/certs" },

    { name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.enabled",                    value = "true" },
    { name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.enabled",       value = "true" },
    { name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.certificate",   value = "/usr/share/elasticsearch/config/certs/tls.crt" },
    { name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.key",           value = "/usr/share/elasticsearch/config/certs/tls.key" },
    { name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.certificate_authorities\\[0\\]", value = "/usr/share/elasticsearch/config/certs/ca.crt" }
  ]


  depends_on = [kubernetes_manifest.es_http_cert, module.eks]
}

# Secret with desired app password (namespace "elasticsearch" so Job can read it)
resource "kubernetes_secret_v1" "es_app_creds" {
  metadata {
    name      = "es-app-user"
    namespace = "sapio" #YQ: Expose elasticsearch app password to sapio app namespaced pods
  }
  data = {
    username = local.es_app_user
    password = random_password.sapio_elasticsearch.result
  }
  type = "Opaque"
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
        restart_policy = "OnFailure"
        container {
          name  = "bootstrap"
          image = "curlimages/curl:8.10.1"
          command = ["/bin/sh","-c"]
          args = [<<-SCRIPT
            set -euo pipefail
            svc="elasticsearch-master.${local.es_namespace}.svc"
            # wait for green
            for i in $(seq 1 120); do
              if curl -sS -u "elastic:$(cat /elastic/elastic_pw)" http://$svc:9200/_cluster/health | grep -q '"status"'; then
                break
              fi
              sleep 5
            done

            # create role with index privileges
            curl -sS -u "elastic:$(cat /elastic/elastic_pw)" \
              -H 'Content-Type: application/json' \
              -X PUT "http://$svc:9200/_security/role/app_writer" \
              -d '{
                "cluster":["monitor"],
                "indices":[{"names":["${local.es_index_pattern}"],
                            "privileges":["create_index","write","create","index","read","view_index_metadata"]}]
              }'

            # create user and assign role
            curl -sS -u "elastic:$(cat /elastic/elastic_pw)" \
              -H 'Content-Type: application/json' \
              -X POST "http://$svc:9200/_security/user/${local.es_app_user}" \
              -d "{\"password\":\"$(cat /app/user_pw)\",\"roles\":[\"app_writer\"]}"
          SCRIPT
          ]
          volume_mount {
            name       = "elastic-creds"
            mount_path = "/elastic"
            read_only  = true
          }
          volume_mount {
            name       = "app-creds"
            mount_path = "/app"
            read_only  = true
          }
        }
        volume {
          name = "elastic-creds"
          secret {
            secret_name = "elasticsearch-master-credentials"
            items {
              key  = "password"
              path = "elastic_pw"
            }
          }
        }
        volume {
          name = "app-creds"
          secret {
            secret_name = random_password.sapio_elasticsearch.result
            items {
              key  = "password"
              path = "user_pw"
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.elasticsearch]
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
}

