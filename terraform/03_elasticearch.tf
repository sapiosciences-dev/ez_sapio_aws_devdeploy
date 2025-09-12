
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
  es_namespace             = "search"
  es_release_name          = "elasticsearch"
  es_app_user              = "app_ingest"
  es_app_password          = random_password.sapio_elasticsearch.result
  es_index_pattern         = "*"

  # service account used by your app pods when they need AWS access (e.g., to read secrets)
  es_app_serviceaccount    = "es-${local.prefix_env}-serviceaccount"
}

resource "helm_release" "elasticsearch" {
  name             = local.es_release_name
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  namespace        = kubernetes_namespace_v1.search.metadata[0].name
  create_namespace = false

  # Basic production-ish values (3 masters that are also data+ingest)
  set {
    name  = "replicas"
    value = 3
  }
  set {
    name  = "minimumMasterNodes"
    value = 2
  }
  set {
    name  = "esJavaOpts"
    value = "-Xms1g -Xmx1g"
  }
  set {
    name  = "resources.requests.cpu"
    value = "1000m"
  }
  set {
    name  = "resources.requests.memory"
    value = "4Gi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "2000m"
  }
  set {
    name  = "resources.limits.memory"
    value = "8Gi"
  }

  # Persistent storage
  set {
    name  = "volumeClaimTemplate.storageClassName"
    value = "gp3"
  }
  set {
    name  = "volumeClaimTemplate.resources.requests.storage"
    value = "100Gi"
  }

  # Avoid node sysctl tweak; switch later if you set vm.max_map_count
  set {
    name  = "esConfig.elasticsearch\\.yml.node\\.store\\.allow_mmap"
    value = "false"
  }

  # Use HTTPS
  set {
    name = "protocol"
    value = "https"
  }
  set {
    name = "secretMounts[0].name"
    value = "http-certs"
  }
  set {
    name = "secretMounts[0].secretName"
    value = kubernetes_secret_v1.es_http_tls.metadata[0].name
  }
  set {
    name = "secretMounts[0].path"
    value = "/usr/share/elasticsearch/config/certs"
  }
  set {
    name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.enabled"
    value = "true"
  }
  set {
    name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.enabled"
    value = "true"
  }
  set {
    name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.certificate"
    value = "/usr/share/elasticsearch/config/certs/tls.crt"
  }
  set {
    name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.key"
    value = "/usr/share/elasticsearch/config/certs/tls.key"
  }
  set {
    name = "esConfig.elasticsearch\\.yml.xpack\\.security\\.http\\.ssl\\.certificate_authorities"
    value = "/usr/share/elasticsearch/config/certs/ca.crt"
  }


  depends_on = [kubernetes_secret_v1.es_http_tls]
}

# Secret with desired app password (namespace "search" so Job can read it)
resource "kubernetes_secret_v1" "es_app_creds" {
  metadata {
    name      = "es-app-user"
    namespace = local.es_namespace
  }
  string_data = {
    username = local.es_app_user
    password = local.es_app_password
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
            secret_name = kubernetes_secret_v1.es_app_creds.metadata[0].name
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
          match_labels = { app = local.sapio_bls_app_name } # matches your Deployment labels
        }
      }
      ports {
        protocol = "TCP"
        port     = 9200
      }
    }
  }
}

