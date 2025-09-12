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
data "aws_ecr_repository" "sapio_app_ecr_repo" {
  name = var.sapio_bls_docker_image_name
}
data "aws_ecr_image" "sapio_app_latest" {
  repository_name = data.aws_ecr_repository.sapio_app_ecr_repo.name
  image_tag       = var.sapio_bls_docker_image_tag
}
resource "random_password" "analytic_server_api_key"{
  length  = 64
  special = false
}

# Define the app name
locals {
  analytic_server_api_key = random_password.analytic_server_api_key.result

  #YQ: You probably want to change these trust stores, although by default they are private to the EKS so not the end of the world to leave them. We have randomized API key anyways.
  #See my github manual https://github.com/sapiosciences/sapioanalyticserver-tutorials
  analytic_server_keystore_password = "123456"
  analytic_server_keystore_base64 = "MIIKFAIBAzCCCb4GCSqGSIb3DQEHAaCCCa8EggmrMIIJpzCCBa4GCSqGSIb3DQEHAaCCBZ8EggWbMIIFlzCCBZMGCyqGSIb3DQEMCgECoIIFQDCCBTwwZgYJKoZIhvcNAQUNMFkwOAYJKoZIhvcNAQUMMCsEFIQfCQ5TegpDnwocrqWOI9ZrYTaKAgInEAIBIDAMBggqhkiG9w0CCQUAMB0GCWCGSAFlAwQBKgQQ"

  analytic_server_app_name = "${local.prefix_env}-analyticserver-app"
  sapio_bls_app_name = "${local.prefix_env}-sapio-app"
  sapio_image = "${data.aws_ecr_repository.sapio_app_ecr_repo.repository_url}@${data.aws_ecr_image.sapio_app_latest.image_digest}"
  jdbc_url_root = "jdbc:mysql://${aws_db_instance.sapio_mysql.address}:${aws_db_instance.sapio_mysql.port}/"
  jdbc_url_suffix = "?trustServerCertificate=true&allowPublicKeyRetrieval=true"
}

###############################
# Analytic server (Deployment)
###############################
resource "kubernetes_deployment_v1" "analytic_server_deployment" {
  metadata { name = "${local.app_name}-analytic-server-deployment" }
  spec {
    # Set a sensible baseline; HPA will change this at runtime
    replicas = 1

    selector {
      match_labels = {
        app  = local.app_name
        role = "analytic-server"
      }
    }

    template {
      metadata {
        labels = {
          app  = local.app_name
          role = "analytic-server"
        }
      }
      spec {
        service_account_name = local.app_serviceaccount

        container {
          name  = "${local.app_name}-analytic-server"
          image = local.sapio_image
          port  {
            name = "analytic-tcp"
            container_port = 8686
          }

          # IMPORTANT for EKS Auto Mode: set realistic requests
          resources {
            requests = {
              cpu    = "8"
              memory = "64Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
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
        }

        # Spread across zones/nodes for resilience
        topology_spread_constraints {
          max_skew           = 1 # The balance across different topology domains (AZs) should not differ by more than this number. Ensures balances on replicas across AZs if above 1 replica.
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = { app = local.app_name, role = "analytic-server" }
          }
        }

      }
    }
  }
}

#############################################
# Stable in-cluster Service for main app use
#############################################
resource "kubernetes_service_v1" "analytic_server_svc" {
  metadata {
    name   = "${local.app_name}-analytic"
    labels = {
      app = local.app_name
      role = "analytic-server"
    }
  }
  spec {
    type     = "ClusterIP"
    selector = {
      app = local.app_name
      role = "analytic-server"
    }
    port {
      name        = "analytic-tcp"
      port        = 8686
      target_port = "analytic-tcp"
      protocol    = "TCP"
    }
  }
}

################################
# HPA (pod-level autoscaling)
################################
resource "kubernetes_horizontal_pod_autoscaler_v2" "analytic_server_hpa" {
  metadata { name = "${local.app_name}-analytic-server-hpa" }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.analytic_server_deployment.metadata[0].name
    }

    min_replicas = 1
    max_replicas = 20

    # Primary signal: CPU utilization
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 65
        }
      }
    }

    # Optional: also watch memory
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type = "Utilization"
          average_utilization = 75
        }
      }
    }

    # Smooth scaling behavior (v2)
    behavior {
      scale_up {
        stabilization_window_seconds = 60
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 300
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 60
        }
      }
    }
  }
}

###########################
# Sapio Main App Deployment
###########################

# Portal User for Sapio App
resource "random_password" "sapio_mysql_portal" {
  length  = 32
  special = true
}
# App user for Sapio App
resource "random_password" "sapio_mysql_app1" {
  length  = 32
  special = true
}

resource "kubernetes_deployment_v1" "sapio_app_deployment" {
  metadata {
    name = "${local.sapio_bls_app_name}-deployment"
    labels = {
      app = local.sapio_bls_app_name
    }
  }

  spec {
    replicas = 1
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
        service_account_name = local.app_serviceaccount
        container {
          image = local.sapio_image
          name  = "${local.sapio_bls_app_name}-sapio-app-pod"

          port {
            container_port = 443
            name = "https"
            protocol = "TCP"
          }
          port {
            container_port = 1099
            name = "RMI"
            protocol = "TCP"
          }
          port {
            contianer_port = 5005
            name = "debug"
            protocol = "TCP"
          }
          port {
            container_port = 8088
            name = "healthcheck"
            protocol = "TCP"
          }

          resources {
            #YQ:  Because Sapio is Java based, we should set the memory to be the same for requests and limits.
            #Tune the CPU as needed.
            limits = {
              cpu    = "4"
              memory = "32Gi"
            }
            requests = {
              cpu    = "0.5"
              memory = "32Gi"
            }
          }

          # Elasticsearch connection details
          env {
            name  = "ES_URL"
            value = "https://elasticsearch-master.${local.es_namespace}.svc:9200"
          }
          env {
            name  = "ES_USERNAME"
            value = local.es_app_user
          }
          env {
            name = "ES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.es_app_creds.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name = "ES_CA_CERT"
            value = "/etc/es-ca/ca.crt"
          }
          volume_mount {
            name       = "es-ca"
            mount_path = "/etc/es-ca"
            read_only  = true
          }
          volume {
            name = "es-ca"
            secret { secret_name = kubernetes_secret_v1.es_http_tls.metadata[0].name }
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
        } #container

        ########### SAPIO ENV VARS ###########
        # JDBC root db url, user, and password.
        env {
          name  = "ROOT_DB_URL"
          value = local.jdbc_url_root + local.jdbc_url_suffix
        }
        env {
          name  = "ROOT_DB_USER"
          value = "sapio"
        }
        env {
          name = "ROOT_DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = kubernetes_secret_v1.rds_mysql_creds.metadata[0].name
              key  = "password"
            }
          }
        }
        env {
          name = "PORTAL_DB_URL"
          value = local.jdbc_url_root + "sapio_portal" + local.jdbc_url_suffix
        }
        env {
          name  = "PORTAL_DB_USER"
          value = "sapio_portal"
        }
        env {
          name = "PORTAL_DB_PASS"
          value = random_password.sapio_mysql_portal.result
        }
        env{
          name = "APP_COUNT"
          value = "1"
        }
        env {
          name = "APP_1_ID"
          value = var.app1_name
        }
        env {
          name = "APP_1_DB_URL"
          value = local.jdbc_url_root + "sapio_app1" + local.jdbc_url_suffix
        }
        env {
          name  = "APP_1_DB_USER"
          value = "sapio_app1"
        }
        env {
          name = "APP_1_DB_PASS"
          value = random_password.sapio_mysql_app1.result
        }
        env {
          name = "VELOXSERVER_DEBUG_ENABLED"
          value = "false" # Set to true to enable remote debugging on port 5005
        }
        env {
          name = "LOG_SENSITIVE"
          value = "false" # Set to true to log sensitive information (e.g., passwords. Not recommended for production.)
        }
        env {
          name = "APP_AUTOSTART"
          value = "true" # Set to false to disable automatic start of the app
        }
        env {
          name = "EXT_SERVER_PROPS"
          value = "" # Any environment variable starting with the string `EXT_SERVER_PROPS` will be appended to the `VeloxServer.properties` file.
          # Example: "veloxity.pdf.autostart=false"
        }
        env {
          name = "VELOXSERVER_JVM_ARGS"
          value = ""
        }
        env {
          name = "SERVER_LICENSE"
          value = var.sapio_server_license_data
        }
        env {
          name = "SapioNativeExecAPIKey"
          value = local.analytic_server_api_key
        }
        env {
          name = "SapioNativeExecHost"
          value = "${kubernetes_service_v1.analytic_server_svc.metadata[0].name}.default.svc"
        }
        env {
          name = "SapioNativeExecPort"
          value = "8686"
        }
        env {
          name = "SapioNativeExecTrustStoreData"
          value = local.analytic_server_keystore_base64
        }
        env {
          name = "SapioNativeExecTrustStorePassword"
          value = local.analytic_server_keystore_password
        }

        # Mount the PVC as a volume in the container
        volume_mount {
          name       = "ebs-k8s-attached-storage"
          mount_path = "/data" # Not sure what data we want to push if the license file is in the container as SERVER_LICENSE base64 env.
        }
        # Define the volume using the PVC
        volume {
          name = "ebs-k8s-attached-storage"

          persistent_volume_claim {
            claim_name = local.ebs_sapio_app_data_claim_name
          }
        } #volume

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
  depends_on = [module.eks]
}