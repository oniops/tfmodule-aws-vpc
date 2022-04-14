# Route53 Private Host Zone
resource "aws_route53_zone" "private" {
  count      = var.create_vpc && var.create_private_domain_hostzone && length(var.context.pri_domain) > 1 ? 1 : 0
  name       = var.context.pri_domain
  vpc {
    vpc_id = concat(aws_vpc.this.*.id, [""])[0]
  }
  depends_on = [aws_vpc.this]
  tags       = merge(local.tags, { Name = var.context.pri_domain })
}
