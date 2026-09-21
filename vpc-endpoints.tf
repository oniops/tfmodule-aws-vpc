################################################################################
# VPC Endpoints (REQUIREMENTS 6.10)
################################################################################

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.vpc_endpoints.gateway

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.context.region}.${each.value}"
  vpc_endpoint_type = "Gateway"

  tags = merge(local.tags_base, { Name = "${local.prefix}-${each.value}-vpce" })

  lifecycle {
    precondition {
      condition     = var.context.region != null
      error_message = "Gateway Endpoint ${each.value} needs context.region to build the service name (RSC-VPCE-01)."
    }
  }
}

locals {
  vpce_subnet_ids = [for k, s in local.vpce_subnets : aws_subnet.this[k].id]
  vpce_security_group_ids = {
    for svc, e in var.vpc_endpoints.interface : svc => concat(
      # Same guard as eni.tf: filter here, report the missing key in the precondition.
      [for n in e.security_group_names : aws_security_group.this[n].id if contains(keys(var.security_groups), n)],
      tolist(e.security_group_ids)
    )
  }
  create_vpce_security_group = length([for svc, ids in local.vpce_security_group_ids : svc if length(ids) == 0]) > 0
}

# Endpoint security group for Interface Endpoints that name no SG (RSC-VPCE-04).
resource "aws_security_group" "vpce" {
  count = local.create_vpce_security_group ? 1 : 0

  name        = "${local.prefix}-vpce-sg"
  description = "Interface VPC Endpoints: HTTPS from the VPC"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags_base, { Name = "${local.prefix}-vpce-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "vpce" {
  for_each = local.create_vpce_security_group ? toset(local.vpc_cidrs) : toset([])

  security_group_id = aws_security_group.vpce[0].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
  description       = "HTTPS from ${each.value}"

  tags = local.tags_base
}

resource "aws_vpc_security_group_ingress_rule" "vpce_ipv6" {
  count = local.create_vpce_security_group && var.enable_ipv6 ? 1 : 0

  security_group_id = aws_security_group.vpce[0].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = aws_vpc.this.ipv6_cidr_block
  description       = "HTTPS from the VPC IPv6 CIDR"

  tags = local.tags_base
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.vpc_endpoints.interface

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.context.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.vpce_subnet_ids
  security_group_ids  = length(local.vpce_security_group_ids[each.key]) > 0 ? local.vpce_security_group_ids[each.key] : [aws_security_group.vpce[0].id]
  private_dns_enabled = each.value.private_dns_enabled
  policy              = each.value.policy

  tags = merge(local.tags_base, { Name = "${local.prefix}-${each.key}-vpce" })

  lifecycle {
    precondition {
      condition     = length(local.vpce_subnets) > 0
      error_message = "vpc_endpoints.interface is declared but vpc_endpoint_subnets is empty (RSC-VPCE-03)."
    }
    precondition {
      condition     = var.context.region != null
      error_message = "Interface Endpoint ${each.key} needs context.region to build the service name (RSC-VPCE-02)."
    }
    precondition {
      condition     = alltrue([for n in each.value.security_group_names : contains(keys(var.security_groups), n)])
      error_message = "Interface Endpoint ${each.key}: security_group_names contains ${join(", ", [for n in each.value.security_group_names : "\"${n}\"" if !contains(keys(var.security_groups), n)])}, which is not a key of security_groups (RSC-VPCE-02). Declared keys: ${join(", ", keys(var.security_groups))}. Use security_group_ids for security groups the caller created."
    }
  }
}
