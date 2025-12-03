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
  bls_subdomain = "bls.${var.env_name}.${var.customer_owned_domain}"
  #YQ: This is a runtime level secret so it can be on ENV.
  analytic_server_api_key = random_password.analytic_server_api_key.result


  #YQ: You probably want to change these trust stores, although by default they are private to the EKS so not the end of the world to leave them. We have randomized API key anyways.
  #See my github manual https://github.com/sapiosciences/sapioanalyticserver-tutorials
  analytic_server_app_name = "${local.prefix_env}-analyticserver-app"
  analytic_server_keystore_password = "123456"
  analytic_server_keystore_base64 = "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"

  sapio_bls_app_name = "${local.prefix_env}-sapio-app"
  jdbc_url_root = "jdbc:mysql://${kubernetes_service_v1.mysql_writer_svc_sapio.metadata[0].name}.${local.sapio_ns}.svc.cluster.local:${aws_db_instance.sapio_mysql.port}/"
  jdbc_replica_url_root = "jdbc:mysql://${kubernetes_service_v1.mysql_replica_svc_sapio.metadata[0].name}.${local.sapio_ns}.svc.cluster.local:${aws_db_instance.sapio_mysql.port}/"
  jdbc_url_suffix = "?trustServerCertificate=true&allowPublicKeyRetrieval=true"
  sql_velox_portal_user = "sapio_portal"

  java_security_dir  = "/opt/java/openjdk/lib/security"
  velox_app1_user = "sapio_app1"
  onlyoffice_jwt_secret = random_password.onlyoffice_jwt_secret.result
  app1_env_value = <<-EOF
TextSearchServerType=elasticsearch
TextSearchUrl=https://${local.es_release_name}-es-http.${local.es_namespace}.svc.cluster.local:9200
AttachmentStorageType=amazons3
AttachmentStorageLocation=${local.s3_bucket_name}
AttachmentAWSRegion=${var.aws_region}
IntegratedOfficeUrl=https://${local.onlyoffice_subdomain}/web-apps/
IntegratedOfficeJwtSecret=${local.onlyoffice_jwt_secret}
EOF
  build_trust_script = <<-EOS
set -eu

# Expect CA mounted as /usr/local/share/ca-certificates/es-ca.crt
if [ ! -s "/usr/local/share/ca-certificates/es-ca.crt" ]; then
  echo "ERROR: missing /usr/local/share/ca-certificates/es-ca.crt" >&2
  exit 1
fi

# Ensure the Debian Java keystore target exists inside the mounted /etc/ssl/certs
mkdir -p "/etc/ssl/certs/java"

# 1) Rebuild OS bundle into mounted /etc/ssl/certs
if command -v update-ca-certificates >/dev/null 2>&1; then
  update-ca-certificates
elif command -v update-ca-trust >/dev/null 2>&1; then
  update-ca-trust extract
else
  echo "WARN: no update-ca-* tool; skipping OS bundle" >&2
fi

# 2) JDK trust: copy defaults to a volume, then either import CA or symlink to Debian's java/cacerts
if [ -d "$K8S_JAVA_SECURITY_DIR" ]; then
  mkdir -p "/work/jdk-security"
  cp -a "$K8S_JAVA_SECURITY_DIR/." "/work/jdk-security/"

  if command -v keytool >/dev/null 2>&1; then
    keytool -importcert -noprompt -trustcacerts \
      -alias es-ca \
      -file "/usr/local/share/ca-certificates/es-ca.crt" \
      -keystore "/work/jdk-security/cacerts" \
      -storepass changeit || echo "WARN: keytool import failed" >&2
  else
    if [ -r "/etc/ssl/certs/java/cacerts" ]; then
      rm -f "/work/jdk-security/cacerts"
      ln -s "/etc/ssl/certs/java/cacerts" "/work/jdk-security/cacerts"
      echo "INFO: linked JDK cacerts -> /etc/ssl/certs/java/cacerts" >&2
    else
      echo "WARN: neither keytool nor /etc/ssl/certs/java/cacerts present; JDK trust may miss CA" >&2
    fi
  fi
fi
EOS
}

# Request ACM certificate for the BLS subdomain
resource "aws_acm_certificate" "bls" {
  domain_name       = local.bls_subdomain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS validation records
resource "aws_route53_record" "bls_validation" {
  for_each = {
    for dvo in aws_acm_certificate.bls.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.root.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# Validate certificate
resource "aws_acm_certificate_validation" "bls" {
  certificate_arn         = aws_acm_certificate.bls.arn
  validation_record_fqdns = [for r in aws_route53_record.bls_validation : r.fqdn]
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

  # The image is large and takes time to pull, then it may wait a grace for terminate.
  timeouts {
    create = "20m"
    update = "20m"
  }

  spec {
    selector {
      match_labels = {
        app  = local.analytic_server_app_name
        role = local.analytic_server_ns
      }
    }

    progress_deadline_seconds = 1200 # 20 minutes

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
        service_account_name = local.analytic_serviceaccount
        automount_service_account_token = true

        init_container {
          name    = "augment-trust"
          # Prefer your app image so we modify the *same* JRE/Python the app uses.
          image   = var.analytic_server_docker_image # WARNING: IMAGE MUST BE THE SAME AS THE MAIN CONTAINER IMAGE SO THEY BELONG TO SAME FILESYSTEM AND TAKE EFFECT.
          #image_pull_policy = "Always"

          command = ["/bin/bash", "-c"]
          args    = [local.build_trust_script]

          # Needs root to write OS trust paths and JDK cacerts
          security_context {
            run_as_user = 0
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }

          # Provide the image-specific JDK path to the script (no braces in script)
          env {
            name = "K8S_JAVA_SECURITY_DIR"
            value = local.java_security_dir
          }

          # CA file placed where update-ca-certificates will read it
          volume_mount {
            name       = "internal-ca"
            mount_path = "/usr/local/share/ca-certificates/es-ca.crt"
            sub_path   = "es-ca.crt"
            read_only  = true
          }
          volume_mount {
            name = "os-certs"
            mount_path = "/etc/ssl/certs"
          }
          volume_mount {
            name = "jdk-security"
            mount_path = "/work/jdk-security"
          }
        }

        container {
          name  = "${local.analytic_server_app_name}-analytic-server"
          image = var.analytic_server_docker_image

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

          port {
            name           = "analytic-tcp"
            container_port = 8686
            protocol       = "TCP"
          }

          readiness_probe {
            exec { command = ["/bin/sh","-c","/usr/bin/nc -z -w 2 127.0.0.1 8686 >/dev/null 2>&1 && exit 0 || exit 1"] }
            period_seconds        = 9
            timeout_seconds = 10
            failure_threshold = 5
          }

          liveness_probe {
            exec { command = ["/bin/sh","-c","/usr/bin/nc -z -w 2 127.0.0.1 8686 >/dev/null 2>&1 && exit 0 || exit 1"] }
            period_seconds        = 11
            timeout_seconds = 10
            failure_threshold = 5
          }

          startup_probe {
            exec { command = ["/bin/sh","-c","/usr/bin/nc -z -w 2 127.0.0.1 8686 >/dev/null 2>&1 && exit 0 || exit 1"] }
            initial_delay_seconds = 20   # give it a short head start
            period_seconds        = 30 # check every 30 seconds
            timeout_seconds       = 10
            success_threshold =  1
            failure_threshold     = 60
          }

          # common init mounts to share filesystem.
          volume_mount {
            name       = "internal-ca"
            mount_path = "/usr/local/share/ca-certificates/es-ca.crt"
            sub_path   = "es-ca.crt"
            read_only  = true
          }
          volume_mount {
            name = "os-certs"
            mount_path = "/etc/ssl/certs"
          }
          volume_mount {
            name = "jdk-security"
            mount_path = "/work/jdk-security"
          }
        } # container
        volume {
          name = "internal-ca"
          secret {
            secret_name = "es-ca"
            items {
              key = "ca.crt"
              path = "es-ca.crt"
            }
          }
        }
        volume {
          name = "os-certs"
          empty_dir {}
        }   # OS bundle output
        volume {
          name = "jdk-security"
          empty_dir {}
        }   # JDK security dir (copied + CA)

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
          type                = "Utilization" # of requests % not limit %. So it can go above 100% if > request % and request % < limit %.
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
          period_seconds = 30
        }
      }
      scale_down {
        stabilization_window_seconds = 300
        select_policy = "Min"
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 600
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
    username = local.sql_velox_portal_user
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
    username = local.velox_app1_user
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

  # The image is large and takes time to pull, then it may wait a grace for terminate.
  timeouts {
    create = "20m"
    update = "20m"
  }

  spec {
    replicas = 1 # DO NOT MODIFY
    progress_deadline_seconds = 1200 # 20 minutes
    strategy {
      # Only run at max 1 server even in case of update. So there will be downtime when BLS updated but we have no choice for now.
      type = "Recreate"
    }
    selector {
      match_labels = {
        app = local.sapio_bls_app_name
      }
    }
    template {
      # BLS Spec and BLS app as selected container for deployment
      metadata {
        labels = {
          app = local.sapio_bls_app_name # WARNING: MUST BE SAME AS THE MAIN CONTAINER IMAGE FOR SAME FILESYSTEM TO TAKE EFFECT.
        }
      }
      spec {
        #YQ: The BLS does not have autoscale capability, so we will directly expose without a service.
        service_account_name = local.app_serviceaccount
        automount_service_account_token = true
        node_selector = {
          "sapio/pool" = "sapio-bls"
        }
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key = "eks.amazonaws.com/compute-type"
                  operator = "NotIn"
                  values = ["auto"]
                }
              }
            }
          }
        }

        init_container {
          name    = "augment-trust"
          # Prefer your app image so we modify the *same* JRE/Python the app uses.
          image   = var.sapio_bls_docker_image
          #image_pull_policy = "Always" # Turn this on if you are going to overwrite a tag.

          command = ["/bin/bash", "-c"]
          args    = [local.build_trust_script]

          # Needs root to write OS trust paths and JDK cacerts
          security_context {
            run_as_user = 0
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }

          # Provide the image-specific JDK path to the script (no braces in script)
          env {
            name = "K8S_JAVA_SECURITY_DIR"
            value = local.java_security_dir
          }

          # CA file placed where update-ca-certificates will read it
          volume_mount {
            name       = "internal-ca"
            mount_path = "/usr/local/share/ca-certificates/es-ca.crt"
            sub_path   = "es-ca.crt"
            read_only  = true
          }
          volume_mount {
            name = "os-certs"
            mount_path = "/etc/ssl/certs"
          }
          volume_mount {
            name = "jdk-security"
            mount_path = "/work/jdk-security"
          }
        }

        container {
          image = var.sapio_bls_docker_image
          name  = "${local.sapio_bls_app_name}-sapio-app-pod"
          port {
            container_port = 8443
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
            name  = "PORTAL_DB_URL"
            value = "${local.jdbc_url_root}sapio_portal${local.jdbc_url_suffix}"
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
            name = "APP_1_DB_REPLICA_URL"
            value = "${local.jdbc_replica_url_root}sapio_app1${local.jdbc_url_suffix}"
          }
          env {
            name = "APP_1_EXT_OPTS"
            value = local.app1_env_value
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
            value = "log.verbose.aws.license.checks=true"
            # Any environment variable starting with the string `EXT_SERVER_PROPS` will be appended to the `VeloxServer.properties` file.
            # Example: "veloxity.pdf.autostart=false"
          }
          env {
            name  = "VELOXSERVER_JVM_ARGS"
            value = "-XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data/oom.hprof -XX:MaxRAMPercentage=75"
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
          volume_mount {
            name       = "onlyoffice-jwt"
            mount_path = "/run/onlyoffice_jwt"
            read_only  = true
          }
          # Mount the PVC as a volume in the container
          volume_mount {
            name       = "ebs-k8s-attached-storage"
            mount_path = "/data" # Not sure what data we want to push if the license file is in the container as SERVER_LICENSE base64 env.
          }

          # common init mounts to share filesystem.
          volume_mount {
            name       = "internal-ca"
            mount_path = "/usr/local/share/ca-certificates/es-ca.crt"
            sub_path   = "es-ca.crt"
            read_only  = true
          }
          volume_mount {
            name = "os-certs"
            mount_path = "/etc/ssl/certs"
            read_only = true
          }
          volume_mount {
            name = "jdk-security"
            mount_path = local.java_security_dir
            read_only = true
          }
        }
        #container
        # Volumes
        volume {
          name = "onlyoffice-jwt"
          secret {
            secret_name = "onlyoffice-jwt-secret"
          }
        }
        # internal-ca: your existing Secret with key "ca.crt"
        volume {
          name = "internal-ca"
          secret {
            secret_name = "es-ca"
            items {
              key = "ca.crt"
              path = "es-ca.crt"
            }
          }
        }
        volume {
          name = "os-certs"
          empty_dir {}
        }   # OS bundle output
        volume {
          name = "jdk-security"
          empty_dir {}
        }   # JDK security dir (copied + CA)
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
  depends_on = [module.eks, kubernetes_service_v1.mysql_writer_svc_sapio, kubernetes_service_v1.mysql_replica_svc_sapio,
    aws_route53_record.onlyoffice_dns,
    kubernetes_job_v1.es_bootstrap_app_user, kubernetes_service_account_v1.sapio_account,
    aws_eks_addon.vpc_cni, kubernetes_secret_v1.es_ca_for_sapio, aws_s3_bucket.cluster_bucket]
}

resource "kubernetes_network_policy_v1" "sapio_allow_egress_all" {
  metadata {
    name      = "allow-egress-all-sapio"
    namespace = kubernetes_namespace.sapio.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress { }
  }
  depends_on = [module.eks]
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
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"          = "HTTP"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"             = "8088"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"             = "/status/healthcheck"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval"         = "10"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout"          = "6"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold"   = "2"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold" = "2"

      "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes" = "deregistration_delay.timeout_seconds=15"

      # NLB settings
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-security-groups" = aws_security_group.sapio_nlb_frontend.id
      "service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules" = "true"

      # TLS at NLB + TLS to backend
      "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"  = aws_acm_certificate_validation.bls.certificate_arn
      "service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "443"
      "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "ssl"
    }
  }

  spec {
    type                         = "LoadBalancer"
    allocate_load_balancer_node_ports = false
    load_balancer_class          = "eks.amazonaws.com/nlb"
    selector = { app = local.sapio_bls_app_name }

    port {
      name        = "https"
      port        = 443     # NLB listener
      target_port = 8443    # BLS HTTPS port inside pod
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
  }

  depends_on = [kubernetes_deployment_v1.sapio_app_deployment]
}

data "aws_lb_hosted_zone_id" "bls_nlb" {
  region             = var.aws_region
  load_balancer_type = "network"
}

# Expose to the world via Route53 by defined subdomain.
resource "aws_route53_record" "bls_alias" {
  depends_on = [
    kubernetes_service_v1.sapio_bls_nlb,
    aws_acm_certificate_validation.bls
  ]

  # This is your *domain* hosted zone (correct)
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.bls_subdomain
  type    = "A"

  alias {
    # NLB DNS name coming from the Service status (correct)
    name    = kubernetes_service_v1.sapio_bls_nlb.status[0].load_balancer[0].ingress[0].hostname

    # Use the NLB hosted zone ID, not the ALB one
    zone_id = data.aws_lb_hosted_zone_id.bls_nlb.id

    evaluate_target_health = false
  }
}