################################################################################
# Private Hosted Zone (REQUIREMENTS 6.13)
################################################################################

locals {
  private_zone_name = var.private_dns == null ? null : (var.private_dns.domain_name != null ? var.private_dns.domain_name : var.context.pri_domain)
}

resource "aws_route53_zone" "private" {
  count = var.private_dns != null ? 1 : 0

  name = local.private_zone_name

  vpc {
    vpc_id = aws_vpc.this.id
  }

  dynamic "vpc" {
    for_each = var.private_dns.additional_vpc_ids
    content {
      vpc_id = vpc.value
    }
  }

  tags = merge(local.tags_base, { Name = local.private_zone_name })

  lifecycle {
    precondition {
      condition     = local.private_zone_name != null
      error_message = "private_dns.domain_name is omitted and context.pri_domain is null (RSC-DNS-01)."
    }
  }
}
