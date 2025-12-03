## Step 1 Locals
locals {
  onlyoffice_subdomain = "docs.${var.env_name}.${var.customer_owned_domain}"
  onlyoffice_ns        = "onlyoffice"

  # Init script to generate a self-signed cert inside the pod
  onlyoffice_tls_init_script = <<-EOS
    set -eu

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

    # Generate dhparam if missing (expensive but once per pod)
    if [ ! -s "$CERT_DIR/dhparam.pem" ]; then
      echo "Generating dhparam.pem..."
      openssl dhparam -out "$CERT_DIR/dhparam.pem" 2048
    fi

    chmod 600 "$CERT_DIR/tls.key"
  EOS
}

## Step 2 Resources

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

resource "kubernetes_secret_v1" "onlyoffice_jwt_secret" {
  metadata {
    name      = "onlyoffice-jwt-secret"
    namespace = local.onlyoffice_ns
  }

  data = {
    jwt-secret = base64encode(random_password.onlyoffice_jwt_secret.result)
  }

  depends_on = [module.eks, kubernetes_namespace.onlyoffice]
}

resource "kubernetes_secret_v1" "sapio_jwt_secret" {
  metadata {
    name      = "onlyoffice-jwt-secret"
    namespace = local.sapio_ns
  }

  data = {
    jwt-secret = base64encode(random_password.onlyoffice_jwt_secret.result)
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
        # --- Init container: generate self-signed cert into shared volume ---
        init_container {
          name  = "generate-onlyoffice-tls"
          image = var.onlyoffice_image

          command = ["/bin/sh", "-c"]
          args    = [local.onlyoffice_tls_init_script]

          volume_mount {
            name       = "onlyoffice-tls"
            mount_path = "/var/www/onlyoffice/Data/certs"
          }
        }

        # --- Main OnlyOffice container ---
        container {
          name  = "documentserver"
          image = var.onlyoffice_image

          # HTTP (for health) and HTTPS (for backend TLS)
          port {
            container_port = 80
          }
          port {
            container_port = 443
          }

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

          # Make HTTPS explicit (matches the cert paths from init container)
          env {
            name = "SSL_CERTIFICATE_PATH"
            value = "/var/www/onlyoffice/Data/certs/tls.crt"
          }
          env {
            name = "SSL_KEY_PATH"
            value = "/var/www/onlyoffice/Data/certs/tls.key"
          }
          env {
            name = "SSL_DHPARAM_PATH"
            value = "/var/www/onlyoffice/Data/certs/dhparam.pem"
          }

          # probes (still fine to hit HTTP 80)
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 20
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          volume_mount {
            name       = "onlyoffice-tls"
            mount_path = "/var/www/onlyoffice/Data/certs"
            read_only  = true
          }
        }

        # Shared EmptyDir volume between init + main container
        volume {
          name = "onlyoffice-tls"
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

resource "null_resource" "onlyoffice_pod_cleanup" {
  # optional, but fine to keep; not referenced in the provisioner
  triggers = {
    ns = "onlyoffice"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOC
      set -eu
      NS="onlyoffice"

      echo "[onlyoffice] Destroy hook: cleaning pods in namespace $NS..."

      # If namespace is already gone, nothing to do
      if ! kubectl get ns "$NS" >/dev/null 2>&1; then
        echo "[onlyoffice] Namespace $NS not found; skipping pod cleanup."
        exit 0
      fi

      # Get *all* pod names in the namespace (running, pending, terminating, whatever)
      PODS="$(kubectl get pod -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' || true)"

      if [ -z "$PODS" ]; then
        echo "[onlyoffice] No pods found in namespace $NS; nothing to clean."
        exit 0
      fi

      for P in $PODS; do
        echo "[onlyoffice] Cleaning pod $P..."

        # 1) Strip any finalizers so K8s won't keep it around
        kubectl patch pod "$P" -n "$NS" \
          -p '{"metadata":{"finalizers":[]}}' \
          --type=merge || true

        # 2) Force-delete the pod (handles running + terminating cases)
        kubectl delete pod "$P" -n "$NS" \
          --force --grace-period=0 --ignore-not-found=true --wait=false || true
      done

      echo "[onlyoffice] Pod cleanup complete in namespace $NS."
    EOC
  }

  depends_on = [
    kubernetes_deployment.onlyoffice_documentserver,
    kubernetes_service_v1.onlyoffice_service,
  ]
}