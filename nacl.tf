################################################################################
# Network ACLs (REQUIREMENTS 6.8). One NACL per stack or for Shared Public.
################################################################################

resource "aws_network_acl" "this" {
  for_each = local.nacls

  vpc_id     = aws_vpc.this.id
  subnet_ids = [for k, s in local.subnets : aws_subnet.this[k].id if s.nacl == each.key]

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.value.name}-nacl" })
}

resource "aws_network_acl_rule" "this" {
  for_each = local.nacl_rules

  network_acl_id = aws_network_acl.this[each.value.nacl].id
  egress         = each.value.egress
  rule_number    = each.value.rule.rule_number
  rule_action    = each.value.rule.rule_action
  protocol       = each.value.rule.protocol
  from_port      = each.value.rule.from_port
  to_port        = each.value.rule.to_port
  icmp_type      = each.value.rule.icmp_type
  icmp_code      = each.value.rule.icmp_code
  cidr_block     = each.value.rule.cidr_block
  # The reserved value "vpc" resolves to the Amazon-assigned VPC IPv6 CIDR (RSC-NACL-06).
  ipv6_cidr_block = each.value.rule.ipv6_cidr_block == "vpc" ? aws_vpc.this.ipv6_cidr_block : each.value.rule.ipv6_cidr_block

  lifecycle {
    precondition {
      condition     = var.enable_ipv6 ? true : each.value.rule.ipv6_cidr_block == null
      error_message = "NACL rule ${each.key} has ipv6_cidr_block but enable_ipv6 is false (RSC-NACL-05)."
    }
  }
}
