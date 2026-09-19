################################################################################
# VPN Gateway and Customer Gateways (REQUIREMENTS 6.11)
################################################################################

resource "aws_vpn_gateway" "this" {
  count = var.vpn_gateway != null && try(var.vpn_gateway.existing_id, null) == null ? 1 : 0

  vpc_id            = aws_vpc.this.id
  amazon_side_asn   = var.vpn_gateway.amazon_side_asn
  availability_zone = var.vpn_gateway.availability_zone

  tags = merge(local.tags_base, { Name = "${local.prefix}-vgw" })
}

resource "aws_vpn_gateway_attachment" "this" {
  count = var.vpn_gateway != null && try(var.vpn_gateway.existing_id, null) != null ? 1 : 0

  vpc_id         = aws_vpc.this.id
  vpn_gateway_id = var.vpn_gateway.existing_id
}

locals {
  vgw_id = try(coalesce(var.vpn_gateway.existing_id, one(aws_vpn_gateway.this[*].id)), null)
}

resource "aws_customer_gateway" "this" {
  for_each = var.customer_gateways

  type        = "ipsec.1"
  bgp_asn     = each.value.bgp_asn
  ip_address  = each.value.ip_address
  device_name = each.value.device_name

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-cgw" })
}
