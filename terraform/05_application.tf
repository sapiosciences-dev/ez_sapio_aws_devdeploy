###############
#
# Deploy containers to run application code, and a Load Balancer to access the app
#
# Logical order: 05
##### "Logical order" refers to the order a human would think of these executions
##### (although Terraform will determine actual order executed)
#
# This repo will be created by container build script in Dockerfile in containers directory.
# It must exist prior to deploy.
resource "random_password" "analytic_server_api_key"{
  length  = 64
  special = false
}

# Define the app name
locals {
  #YQ: This is a runtime level secret so it can be on ENV.
  analytic_server_api_key = random_password.analytic_server_api_key.result


  #YQ: You probably want to change these trust stores, although by default they are private to the EKS so not the end of the world to leave them. We have randomized API key anyways.
  #See my github manual https://github.com/sapiosciences/sapioanalyticserver-tutorials
  analytic_server_app_name = "${local.prefix_env}-analyticserver-app"
  analytic_server_keystore_password = "123456"
  analytic_server_keystore_base64 = "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"

  sapio_bls_app_name = "${local.prefix_env}-sapio-app"
  jdbc_url_root = "jdbc:mysql://${aws_db_instance.sapio_mysql.address}:${aws_db_instance.sapio_mysql.port}/"
  jdbc_url_suffix = "?trustServerCertificate=true&allowPublicKeyRetrieval=true"
}

###############################
# Analytic server (Deployment)
###############################
resource "kubernetes_deployment_v1" "analytic_server_deployment" {
  count = var.analytic_enabled ? 1 : 0
  metadata {
    name = "${local.analytic_server_app_name}-analytic-server-deployment"
    namespace = local.analytic_server_ns
  }
  spec {
    # Set a sensible baseline; HPA will change this at runtime
    replicas = 1

    selector {
      match_labels = {
        app  = local.analytic_server_app_name
        role = local.analytic_server_ns
      }
    }

    template {
      metadata {
        labels = {
          app  = local.analytic_server_app_name
          role = local.analytic_server_ns
        }
      }
      spec {
        node_selector = {
          "eks.amazonaws.com/compute-type" = "auto"
        }
        service_account_name = local.app_serviceaccount

        container {
          name  = "${local.analytic_server_app_name}-analytic-server"
          image = var.analytic_server_docker_image
          port  {
            name = "analytic-tcp"
            container_port = 8686
          }

          # IMPORTANT for EKS Auto Mode: set realistic requests
          resources {
            requests = {
              cpu    = var.analytic_server_cpu_request
              memory = var.analytic_server_memory_request
              ephemeral-storage = var.analytic_server_temp_storage_size
            }
            limits = {
              cpu    = var.analytic_server_cpu_limit
              memory = var.analytic_server_memory_limit
              ephemeral-storage = var.analytic_server_temp_storage_size
            }
          }

          env {
            name = "COMPATIBILITY_MODE"
            value = "true"
          }
          env {
            name = "SAPIO_EXEC_SERVER_API_KEY"
            value = local.analytic_server_api_key
          }
          env {
            name = "SAPIO_EXEC_SERVER_KEYSTORE_PASSWORD"
            value = local.analytic_server_keystore_password
          }
          env {
            name = "SAPIO_EXEC_SERVER_KEYSTORE_BASE64"
            value = local.analytic_server_keystore_base64
          }

          readiness_probe {
            tcp_socket { port = "analytic-tcp" }
            initial_delay_seconds = 30
            period_seconds        = 5
          }

          liveness_probe {
            tcp_socket { port = "analytic-tcp" }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          #volume
          volume_mount {
            name       = "internal-ca"
            mount_path = "/certificates"
            read_only  = true
          }
        } # container
        volume {
          name = "internal-ca"
          secret {
            secret_name = "es-ca"     # created per-namespace above
            items {
              key  = "ca.crt"
              path = "ca.crt"         # keep .crt extension
            }
          }
        }

        # Spread across zones/nodes for resilience
        topology_spread_constraint {
          max_skew           = 1 # The balance across different topology domains (AZs) should not differ by more than this number. Ensures balances on replicas across AZs if above 1 replica.
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = { app = local.analytic_server_app_name, role = local.analytic_server_ns }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service_account_v1.analytic_server_account, kubernetes_secret_v1.es_ca_for_as]
}

#############################################
# Stable in-cluster Service for main app use
#############################################
resource "kubernetes_service_v1" "analytic_server_svc" {
  count = var.analytic_enabled ? 1 : 0
  metadata {
    name   = "${local.analytic_server_app_name}-analytic"
    namespace = local.analytic_server_ns
    labels = {
      app = local.analytic_server_app_name
      role = local.analytic_server_ns
    }
  }
  spec {
    type     = "ClusterIP"
    selector = {
      app = local.analytic_server_app_name
      role = local.analytic_server_ns
    }
    port {
      name        = "analytic-tcp"
      port        = 8686
      target_port = "analytic-tcp"
      protocol    = "TCP"
    }
  }
  depends_on = [kubernetes_deployment_v1.analytic_server_deployment]
}

################################
# HPA (pod-level autoscaling)
################################
resource "kubernetes_horizontal_pod_autoscaler_v2" "analytic_server_hpa" {
  count = var.analytic_enabled ? 1 : 0
  metadata {
    name = "${local.analytic_server_app_name}-analytic-server-hpa"
    namespace = local.analytic_server_ns
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.analytic_server_deployment[count.index].metadata[0].name
    }

    min_replicas = var.analytic_server_min_replicas
    max_replicas = var.analytic_server_max_replicas

    # Signals
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.analytic_server_target_cpu_utilization_percentage
        }
      }
    }
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type = "Utilization"
          average_utilization = var.analytic_server_target_memory_utilization_percentage
        }
      }
    }

    # Smooth scaling behavior (v2)
    behavior {
      scale_up {
        stabilization_window_seconds = 60
        select_policy = "Max"
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 300
        select_policy = "Min"
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 60
        }
      }
    }
  }
  depends_on = [kubernetes_deployment_v1.analytic_server_deployment]
}

###########################
# Sapio Main App Deployment
###########################

# Portal User for Sapio App
resource "random_password" "sapio_mysql_portal" {
  length  = 32
  special = true
}
resource "kubernetes_secret_v1" "mysql_portal_creds" {
  metadata {
    name      = "mysql-portal-user"
    namespace = local.sapio_ns # only sapio app namespace pods can read this secret.
  }
  data = {
    username = local.sql_root_user
    password = random_password.sapio_mysql_portal.result
  }
  type = "Opaque"
  depends_on = [kubernetes_namespace.sapio]
}
# App user for Sapio App
resource "random_password" "sapio_mysql_app1" {
  length  = 32
  special = true
}
resource "kubernetes_secret_v1" "mysql_app1_creds" {
  metadata {
    name      = "mysql-app1-user"
    namespace = local.sapio_ns # only sapio app namespace pods can read this secret.
  }
  data = {
    username = local.sql_root_user
    password = random_password.sapio_mysql_app1.result
  }
  type = "Opaque"
  depends_on = [kubernetes_namespace.sapio]
}

resource "kubernetes_deployment_v1" "sapio_app_deployment" {
  metadata {
    name = "${local.sapio_bls_app_name}-deployment"
    namespace = local.sapio_ns
    labels = {
      app = local.sapio_bls_app_name
    }
  }

  spec {
    replicas = 1 # DO NOT MODIFY
    selector {
      match_labels = {
        app = local.sapio_bls_app_name
      }
    }
    template {
      # BLS Spec and BLS app as selected container for deployment
      metadata {
        labels = {
          app = local.sapio_bls_app_name
        }
      }
      spec {
        #YQ: The BLS does not have autoscale capability, so we will directly expose without a service.
        service_account_name = local.app_serviceaccount
        node_selector = {
          "sapio/pool" = "sapio-bls"
        }
        container {
          image = var.sapio_bls_docker_image
          name  = "${local.sapio_bls_app_name}-sapio-app-pod"
          port {
            container_port = 22
            name           = "ssh"
            protocol       = "TCP"
          }
          port {
            container_port = 443
            name           = "https"
            protocol       = "TCP"
          }
          port {
            container_port = 1099
            name           = "rmi"
            protocol       = "TCP"
          }
          port {
            container_port = 5005
            name           = "debug"
            protocol       = "TCP"
          }
          port {
            container_port = 8088
            name           = "healthcheck"
            protocol       = "TCP"
          }

          resources {
            #YQ:  Because Sapio is Java based, we should set the memory to be the same for requests and limits.
            #Tune the CPU as needed.
            requests = {
              cpu    = var.bls_server_cpu_request
              memory = var.bls_server_memory_request
              ephemeral-storage = var.bls_server_temp_storage_size
            }
            limits = {
              cpu    = var.bls_server_cpu_limit
              memory = var.bls_server_memory_limit
              ephemeral-storage = var.bls_server_temp_storage_size
            }
          }

          # Elasticsearch connection details
          env {
            name  = "ES_URL"
            value = "https://elasticsearch-master.${local.es_namespace}.svc:9200"
          }
          env {
            name  = "ES_USER"
            value = local.es_app_user
          }
          env {
            name = "ES_PASS"
            value_from {
              secret_key_ref {
                name = local.es_app_secret_name
                key  = "password"
              }
            }
          }
          env {
            name  = "ES_CA_CERT"
            value = "/certificates/es_ca/ca.crt"
          }
          # Add environment variable using Kubernetes Downward API to get node name
          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          # Add environment variable for the region
          env {
            name  = "AWS_REGION"
            value = var.aws_region # This is the region where the EKS cluster is deployed
          }
          ########### SAPIO ENV VARS ###########
          # JDBC root db url, user, and password.
          env {
            name  = "ROOT_DB_URL"
            value = "${local.jdbc_url_root}${local.jdbc_url_suffix}"
          }
          env {
            name  = "ROOT_DB_USER"
            value = "sapio"
          }
          env {
            name = "ROOT_DB_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.mysql_root_creds.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "PORTAL_DB_URL"
            value = "${local.jdbc_url_root}sapio_portal${local.jdbc_url_suffix}"
          }
          env {
            name  = "PORTAL_DB_USER"
            value = "sapio_portal"
          }
          env {
            name  = "PORTAL_DB_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.mysql_portal_creds.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "APP_COUNT"
            value = "1"
          }
          env {
            name  = "APP_1_ID"
            value = var.app1_name
          }
          env {
            name  = "APP_1_DB_URL"
            value = "${local.jdbc_url_root}sapio_app1${local.jdbc_url_suffix}"
          }
          env {
            name  = "APP_1_DB_USER"
            value = "sapio_app1"
          }
          env {
            name  = "APP_1_DB_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.mysql_app1_creds.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "VELOXSERVER_DEBUG_ENABLED"
            value = "false" # Set to true to enable remote debugging on port 5005
          }
          env {
            name  = "LOG_SENSITIVE"
            value = "false"
            # Set to true to log sensitive information (e.g., passwords. Not recommended for production.)
          }
          env {
            name  = "APP_AUTOSTART"
            value = "true" # Set to false to disable automatic start of the app
          }
          env {
            name  = "EXT_SERVER_PROPS"
            value = ""
            # Any environment variable starting with the string `EXT_SERVER_PROPS` will be appended to the `VeloxServer.properties` file.
            # Example: "veloxity.pdf.autostart=false"
          }
          env {
            name  = "VELOXSERVER_JVM_ARGS"
            value = ""
          }
          env {
            name  = "SERVER_LICENSE"
            value = var.sapio_server_license_data
          }
          env {
            name  = "SapioNativeExecAPIKey"
            value = local.analytic_server_api_key
          }
          dynamic "env" {
            for_each = var.analytic_enabled ? [1] : []
            content {
              name  = "SapioNativeExecHost"
              value = "${kubernetes_service_v1.analytic_server_svc[0].metadata[0].name}.${kubernetes_service_v1.analytic_server_svc[0].metadata[0].namespace}.svc"
            }
          }
          env {
            name  = "SapioNativeExecPort"
            value = "8686"
          }
          env {
            name  = "SapioNativeExecTrustStoreData"
            value = local.analytic_server_keystore_base64
          }
          env {
            name  = "SapioNativeExecTrustStorePassword"
            value = local.analytic_server_keystore_password
          }
          env {
            name  = "USE_SYSTEM_CA_CERTS"
            value = "1"
          }

          #volume
          # Mount the PVC as a volume in the container
          volume_mount {
            name       = "ebs-k8s-attached-storage"
            mount_path = "/data" # Not sure what data we want to push if the license file is in the container as SERVER_LICENSE base64 env.
          }
          volume_mount {
            name       = "internal-ca"
            mount_path = "/certificates"
            read_only  = true
          }
        }
        #container
        volume {
          name = "internal-ca"
          secret {
            secret_name = "es-ca"     # created per-namespace above
            items {
              key  = "ca.crt"
              path = "ca.crt"         # keep .crt extension
            }
            # optional = false        # default; add if you want to be explicit
          }
        }
        # Define the volume using the PVC
        volume {
          name = "ebs-k8s-attached-storage"

          persistent_volume_claim {
            claim_name = local.ebs_sapio_app_data_claim_name
          }
        }

        # This is necessary when using EKS Auto Mode to share the EBS PV among pods
        # see https://docs.aws.amazon.com/eks/latest/userguide/auto-troubleshoot.html#auto-troubleshoot-share-pod-volumes
        security_context {
          se_linux_options {
            level = "s0:c123,c124,c125"
          }
        } #security_context
      }   #spec (template)
    }     #template
  }       #spec (resource)

  # Give time for the cluster to complete (controllers, RBAC and IAM propagation)
  # See https://github.com/setheliot/eks_auto_mode/blob/main/docs/separate_configs.md
  depends_on = [module.eks, aws_db_instance.sapio_mysql, aws_db_instance.sapio_mysql_replica,
    kubernetes_job_v1.es_bootstrap_app_user, kubernetes_service_account_v1.sapio_account,
    aws_eks_addon.vpc_cni, kubernetes_secret_v1.es_ca_for_sapio]

}

# There is no LB support. But replica = 1 means there is no replica. This is the easiest way to export the app.
resource "kubernetes_service_v1" "sapio_bls_nlb" {
  wait_for_load_balancer = true
  metadata {
    name      = "${local.sapio_bls_app_name}-bls-gate"
    namespace = local.sapio_ns
    labels    = { app = local.sapio_bls_app_name }
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"

      # Tell AWS LB Controller to create an NLB and target pod IPs directly
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"

      # Health check (TCP on 443) — or switch to HTTP 8088 if you have an HTTP health endpoint
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "TCP"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"     = "8088"
    }
  }
  spec {
    type     = "LoadBalancer"
    selector = { app = local.sapio_bls_app_name }   # same pods
    port {
      name        = "https"
      port        = 443          # NLB listener port
      target_port = 443
      protocol    = "TCP"
    }
    port {
      name        = "rmi"
      port        = 1099
      target_port = 1099
      protocol    = "TCP"
    }
    port {
      name        = "debug"
      port        = 5005
      target_port = 5005
      protocol    = "TCP"
    }
    port {
      name        = "healthcheck"
      port        = 8088
      target_port = 8088
      protocol    = "TCP"
    }
    port {
      name = "ssh"
      port = 22
      target_port = 22
      protocol = "TCP"
    }
  }
  depends_on = [kubernetes_deployment_v1.sapio_app_deployment]
}