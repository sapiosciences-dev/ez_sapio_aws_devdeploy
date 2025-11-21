###############
#
# Customer Owned Domains
# This section must refer to a domain already managed by AWS Route 53.
# This is because OnlyOffice requires a browser-trusted certificate and AWS cannot generate one with its own elastic domain by its security policy.
#
# Logical order: 01
###############

data "aws_route53_zone" "root" {
  name         = var.customer_owned_domain
  private_zone = false
}

# empty block is intentionally to retrieve alb zone ID hosting data.
data "aws_elb_hosted_zone_id" "alb" {}