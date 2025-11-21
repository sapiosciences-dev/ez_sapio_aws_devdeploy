locals {
  onlyoffice_subdomain = "docs.${var.env_name}.${var.customer_owned_domain}"
  onlyoffice_ns        = "onlyoffice"
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
resource "kubernetes_secret_v1" "onlyoffice_jwt_secret" {
  metadata {
    name      = "onlyoffice-jwt-secret"
    namespace = local.onlyoffice_ns
  }

  data = {
    jwt-secret = base64encode(random_password.onlyoffice_jwt_secret.result)
  }

  depends_on = [module.eks]
}
resource "kubernetes_secret_v1" "sapio_jwt_secret" {
  metadata {
    name      = "onlyoffice-jwt-secret"
    namespace = local.sapio_ns
  }

  data = {
    jwt-secret = base64encode(random_password.onlyoffice_jwt_secret.result)
  }

  depends_on = [module.eks]
}

# Create onlyoffice app for deployment
resource "kubernetes_deployment" "onlyoffice_documentserver" {
  depends_on = [module.eks]

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
        container {
          name  = "documentserver"
          image = var.onlyoffice_image

          # HTTP only - ALB will terminate HTTPS
          port {
            container_port = 80
          }

          env {
            # Allow self signed certificates for callbacks/internal storage if needed
            name  = "USE_UNAUTHORIZED_STORAGE"
            value = "true"
          }

          env {
            name = "JWT_ENABLED"
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

          # probes
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
        }
      }
    }
  }
}

resource "kubernetes_service" "onlyoffice_service" {
  depends_on = [
    module.eks,
    kubernetes_deployment.onlyoffice_documentserver
  ]

  metadata {
    name      = "onlyoffice-documentserver"
    namespace = local.onlyoffice_ns
    labels = {
      app = "onlyoffice-documentserver"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "onlyoffice-documentserver"
    }

    //port 80 as internal service, ALB will handle HTTPS
    port {
      name        = "http"
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}

# Create ALB Ingress for OnlyOffice
resource "kubernetes_ingress_v1" "onlyoffice_ingress" {
  depends_on = [
    module.eks,
    aws_acm_certificate_validation.onlyoffice,
    kubernetes_service.onlyoffice_service
  ]

  metadata {
    name      = "onlyoffice-documentserver"
    namespace = local.onlyoffice_ns

    annotations = {
      "kubernetes.io/ingress.class"                 = "alb"
      "alb.ingress.kubernetes.io/scheme"            = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"       = "ip"
      "alb.ingress.kubernetes.io/listen-ports"      = "[{\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/certificate-arn"   = aws_acm_certificate_validation.onlyoffice.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"      = "443"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = local.onlyoffice_subdomain

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.onlyoffice_service.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

# Expose to the world via Route53 by defined subdomain.
resource "aws_route53_record" "onlyoffice_dns" {
  depends_on = [
    kubernetes_ingress_v1.onlyoffice_ingress,
    aws_acm_certificate_validation.onlyoffice
  ]

  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.onlyoffice_subdomain
  type    = "A"

  alias {
    name                   = kubernetes_ingress_v1.onlyoffice_ingress.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.aws_elb_hosted_zone_id.alb.id
    evaluate_target_health = false
  }
}