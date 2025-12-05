## Step 1 Locals
locals {
  onlyoffice_subdomain = "docs.${var.env_name}.${var.customer_owned_domain}"
  onlyoffice_ns        = "onlyoffice"

  # Init script to generate a self-signed cert AND extract the plugin
  onlyoffice_tls_init_script = <<-EOS
    set -eu

    # --- PART 1: TLS GENERATION ---
    CERT_DIR="/var/www/onlyoffice/Data/certs"
    mkdir -p "$CERT_DIR"

    # Generate key+cert if missing
    if [ ! -s "$CERT_DIR/tls.key" ] || [ ! -s "$CERT_DIR/tls.crt" ]; then
      echo "Generating self-signed certificate for ${local.onlyoffice_subdomain}..."
      openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/tls.key" \
        -out "$CERT_DIR/tls.crt" \
        -subj "/CN=${local.onlyoffice_subdomain}"
    fi

    # Generate dhparam if missing
    if [ ! -s "$CERT_DIR/dhparam.pem" ]; then
      echo "Generating dhparam.pem..."
      openssl dhparam -out "$CERT_DIR/dhparam.pem" 2048
    fi

    chmod 600 "$CERT_DIR/tls.key"

    # --- PART 2: PLUGIN EXTRACTION ---
    echo "Starting Veloxity Plugin Extraction..."

    # We need to install unzip if it's not present (the base image is often minimal)
    # If the image is Ubuntu/Debian based:
    if ! command -v unzip &> /dev/null; then
        echo "Unzip not found. Attempting install..."
        apt-get update && apt-get install -y unzip || echo "Unzip install failed, hoping for the best..."
    fi

    PLUGIN_DEST="/var/www/onlyoffice/documentserver/sdkjs-plugins/veloxity-1.3.0"

    # Ensure destination exists
    mkdir -p "$PLUGIN_DEST"

    # Extract directly from the mounted ConfigMap (read-only) to the shared volume
    # -o: overwrite without prompting
    # -d: destination directory
    # -j: junk paths (flatten) - REMOVED this flag because we want the internal structure if needed,
    #     but based on your request, we are extracting specifically to the target folder.

    # NOTE: The zip contains "veloxity-1.3.0/code.js".
    # We want the contents of that folder to end up in "$PLUGIN_DEST".
    # We extract to a temporary spot then move, to handle the folder nesting cleanly.

    TMP_EXTRACT="/tmp/veloxity_extract"
    mkdir -p "$TMP_EXTRACT"

    echo "Unzipping file..."
    unzip -o /plugin-source/veloxity_plugin.zip -d "$TMP_EXTRACT"

    echo "Moving files to final destination..."
    # Move the CONTENTS of the extracted 'veloxity-1.3.0' folder to our target mount
    cp -r "$TMP_EXTRACT/veloxity-1.3.0/." "$PLUGIN_DEST/"

    echo "Plugin extraction complete."
    ls -la "$PLUGIN_DEST"
  EOS
}

## Step 2 Resources

resource "kubernetes_config_map" "veloxity_plugin" {
  metadata {
    name      = "veloxity-plugin-zip"
    namespace = local.onlyoffice_ns
  }

  # YQ WARNING: total config map data in EKS must be under 1MB, not per row but entire config map.
  binary_data = {
    "veloxity_plugin.zip" = "${filebase64("${path.module}/files/veloxity-onlyoffice-plugin-1.3.0.zip")}"
  }

  depends_on = [kubernetes_namespace.onlyoffice]
}

# Prove the domain ownership to AWS Certificate Manager (ACM) for the OnlyOffice subdomain from Route53.
resource "aws_acm_certificate" "onlyoffice" {
  domain_name       = local.onlyoffice_subdomain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "onlyoffice_validation" {
  for_each = {
    for dvo in aws_acm_certificate.onlyoffice.domain_validation_options :
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

resource "aws_acm_certificate_validation" "onlyoffice" {
  certificate_arn         = aws_acm_certificate.onlyoffice.arn
  validation_record_fqdns = [for r in aws_route53_record.onlyoffice_validation : r.fqdn]
}

#Our API Key so only our app can access the document server.
#Make a mirror copy in onlyoffice and in sapio each.
resource "random_password" "onlyoffice_jwt_secret" {
  length  = 32
  special = false
}

resource "kubernetes_namespace" "onlyoffice" {
  metadata {
    name = local.onlyoffice_ns
  }

  depends_on = [module.eks]
}

# 2. THE CLEANER (The Dependent)
resource "null_resource" "onlyoffice_cleanup" {
  # We "store" the variables here so they are available during destroy via 'self.triggers'
  triggers = {
    namespace    = local.onlyoffice_ns
    cluster_name = local.cluster_name
    region       = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    # Using self.triggers avoids "Invalid reference" error
    command = <<-EOC
      set -e
      REGION="${self.triggers.region}"
      CLUSTER="${self.triggers.cluster_name}"
      NS="${self.triggers.namespace}"

      echo "[onlyoffice] Authenticating..."
      aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

      echo "[onlyoffice] Pre-cleaning namespace $NS..."

      # Clean Services (Unblocks Load Balancers)
      kubectl get svc -n "$NS" --no-headers -o custom-columns=":metadata.name" | while read svc; do
        kubectl patch svc "$svc" -n "$NS" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
      done
      kubectl delete svc --all -n "$NS" --timeout=10s --wait=false || true

      # Clean Pods (Unblocks Namespace Termination)
      kubectl get pods -n "$NS" --no-headers -o custom-columns=":metadata.name" | while read pod; do
        kubectl patch pod "$pod" -n "$NS" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
        kubectl delete pod "$pod" -n "$NS" --grace-period=0 --force --ignore-not-found --wait=false || true
      done

      sleep 5
    EOC
  }

  # THIS IS VALID: The Cleaner depends on the Namespace.
  # Destruction Order: Cleaner (runs script) -> then Namespace (API call).
  depends_on = [
    kubernetes_namespace.onlyoffice
  ]
}

resource "kubernetes_secret_v1" "onlyoffice_jwt_secret" {
  metadata {
    name      = "onlyoffice-jwt-secret"
    namespace = local.onlyoffice_ns
  }

  data = {
    jwt-secret = random_password.onlyoffice_jwt_secret.result
  }

  depends_on = [module.eks, kubernetes_namespace.onlyoffice]
}

resource "kubernetes_secret_v1" "sapio_jwt_secret" {
  metadata {
    name      = "onlyoffice-jwt-secret"
    namespace = local.sapio_ns
  }

  data = {
    jwt-secret = random_password.onlyoffice_jwt_secret.result
  }

  depends_on = [module.eks, kubernetes_namespace.onlyoffice]
}

## Step 3 Pod Deployment
resource "kubernetes_deployment" "onlyoffice_documentserver" {
  depends_on = [module.eks, kubernetes_namespace.onlyoffice]

  metadata {
    name      = "onlyoffice-documentserver"
    namespace = local.onlyoffice_ns
    labels = {
      app = "onlyoffice-documentserver"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "onlyoffice-documentserver"
      }
    }

    template {
      metadata {
        labels = {
          app = "onlyoffice-documentserver"
        }
      }

      spec {
        termination_grace_period_seconds = 0
        # --- Init container (TLS + Plugin) ---
        init_container {
          name  = "generate-onlyoffice-tls"
          image = var.onlyoffice_image

          # Run as root to ensure we can install unzip and write to shared dirs
          security_context {
            run_as_user = 0
          }

          command = ["/bin/sh", "-c"]
          args    = [local.onlyoffice_tls_init_script]

          volume_mount {
            name       = "onlyoffice-tls"
            mount_path = "/var/www/onlyoffice/Data/certs"
          }

          # Mount the source Zip (Read Only from ConfigMap)
          volume_mount {
            name       = "plugin-source-zip"
            mount_path = "/plugin-source"
          }

          # Mount the shared storage where we will write the extracted files
          volume_mount {
            name       = "plugin-storage"
            mount_path = "/var/www/onlyoffice/documentserver/sdkjs-plugins/veloxity-1.3.0"
          }
        }

        # --- Main OnlyOffice container ---
        container {
          name  = "documentserver"
          image = var.onlyoffice_image

          resources {
            requests = {
              cpu                 = var.onlyoffice_cpu_request
              memory              = var.onlyoffice_memory_request
              ephemeral-storage   = "4Gi"
            }
          }

          port {
            container_port = 80
          }
          port {
            container_port = 443
          }

          # --- FIXED ENV BLOCKS (Expanded to multi-line) ---
          env {
            name  = "USE_UNAUTHORIZED_STORAGE"
            value = "true"
          }

          env {
            name  = "JWT_ENABLED"
            value = "true"
          }

          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = "onlyoffice-jwt-secret"
                key  = "jwt-secret"
              }
            }
          }

          env {
            name  = "SSL_CERTIFICATE_PATH"
            value = "/var/www/onlyoffice/Data/certs/tls.crt"
          }

          env {
            name  = "SSL_KEY_PATH"
            value = "/var/www/onlyoffice/Data/certs/tls.key"
          }

          env {
            name  = "SSL_DHPARAM_PATH"
            value = "/var/www/onlyoffice/Data/certs/dhparam.pem"
          }

          # --- Probes ---
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 180
            period_seconds        = 30
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          # Mount TLS certs
          volume_mount {
            name       = "onlyoffice-tls"
            mount_path = "/var/www/onlyoffice/Data/certs"
            read_only  = true
          }

          # Mount the plugin folder
          volume_mount {
            name       = "plugin-storage"
            mount_path = "/var/www/onlyoffice/documentserver/sdkjs-plugins/veloxity-1.3.0"
          }
        }

        # --- VOLUMES ---
        volume {
          name = "onlyoffice-tls"
          empty_dir {}
        }

        # Volume 1: Holds the raw zip file from Terraform ConfigMap
        volume {
          name = "plugin-source-zip"
          config_map {
            name = "veloxity-plugin-zip"
          }
        }

        # Volume 2: Shared scratch space for the specific plugin folder
        volume {
          name = "plugin-storage"
          empty_dir {}
        }
      }
    }
  }
}

## Step 4 NLB
resource "kubernetes_service_v1" "onlyoffice_service" {
  wait_for_load_balancer = true

  metadata {
    name      = "onlyoffice-documentserver"
    namespace = local.onlyoffice_ns
    labels    = { app = "onlyoffice-documentserver" }

    annotations = {
      # Internet-facing NLB
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"

      # Health check (you can use TCP 443 or HTTP 80; TCP is simplest)
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"            = "TCP"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"               = "443"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval"           = "10"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout"            = "6"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold"   = "2"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold" = "2"

      "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes" = "deregistration_delay.timeout_seconds=15"

      # NLB specifics
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"

      # Reuse the same front-end SG you use for BLS so inbound 443 is actually allowed
      "service.beta.kubernetes.io/aws-load-balancer-security-groups" = aws_security_group.sapio_nlb_frontend.id
      "service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules" = "true"

      # TLS at NLB using ACM cert (use the VALIDATED ARN, as you do for BLS)
      "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"  = aws_acm_certificate_validation.onlyoffice.certificate_arn
      "service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "443"

      # NLB → pod also over TLS (your self-signed cert)
      "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "ssl"
    }
  }

  spec {
    type                             = "LoadBalancer"
    allocate_load_balancer_node_ports = false
    load_balancer_class              = "eks.amazonaws.com/nlb"

    selector = { app = "onlyoffice-documentserver" }

    # NLB listens on 443 with ACM, forwards TLS to pod:443
    port {
      name        = "https"
      port        = 443      # NLB listener
      target_port = 443      # OnlyOffice HTTPS port inside pod
      protocol    = "TCP"
    }
  }

  # Make sure the cert is Issued before NLB tries to use it
  depends_on = [aws_acm_certificate_validation.onlyoffice, kubernetes_namespace.onlyoffice]
}

## STEP 5 Route53

data "aws_lb_hosted_zone_id" "onlyoffice_nlb" {
  region             = var.aws_region
  load_balancer_type = "network"
}

resource "aws_route53_record" "onlyoffice_dns" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.onlyoffice_subdomain   # docs.env.customer.com
  type    = "A"

  alias {
    name                   = kubernetes_service_v1.onlyoffice_service.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.aws_lb_hosted_zone_id.onlyoffice_nlb.id
    evaluate_target_health = false
  }

  depends_on = [
    kubernetes_service_v1.onlyoffice_service,
    aws_acm_certificate_validation.onlyoffice, kubernetes_namespace.onlyoffice
  ]
}