################################################################################
# Security Groups and rules (REQUIREMENTS 6.6, RSC-SG-01..07). Rules are separate
# resources so callers may add their own without disturbing this plan.
################################################################################

resource "aws_security_group" "this" {
  for_each = var.security_groups

  name        = "${local.prefix}-${each.key}-sg"
  description = each.value.description
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.sg_ingress_rules

  security_group_id = aws_security_group.this[each.value.sg].id

  ip_protocol                  = each.value.rule.ip_protocol
  from_port                    = each.value.rule.from_port
  to_port                      = each.value.rule.to_port
  cidr_ipv4                    = each.value.rule.cidr_ipv4
  cidr_ipv6                    = each.value.rule.cidr_ipv6
  prefix_list_id               = each.value.rule.prefix_list_id
  referenced_security_group_id = each.value.rule.referenced_security_group_name != null ? aws_security_group.this[each.value.rule.referenced_security_group_name].id : each.value.rule.referenced_security_group_id
  description                  = each.value.rule.description

  tags = merge(local.tags_base, var.security_groups[each.value.sg].tags)
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.sg_egress_rules

  security_group_id = aws_security_group.this[each.value.sg].id

  ip_protocol                  = each.value.rule.ip_protocol
  from_port                    = each.value.rule.from_port
  to_port                      = each.value.rule.to_port
  cidr_ipv4                    = each.value.rule.cidr_ipv4
  cidr_ipv6                    = each.value.rule.cidr_ipv6
  prefix_list_id               = each.value.rule.prefix_list_id
  referenced_security_group_id = each.value.rule.referenced_security_group_name != null ? aws_security_group.this[each.value.rule.referenced_security_group_name].id : each.value.rule.referenced_security_group_id
  description                  = each.value.rule.description

  tags = merge(local.tags_base, var.security_groups[each.value.sg].tags)
}

################################################################################
# Network Interfaces (RSC-ENI-01..11)
################################################################################

locals {
  eni_security_group_ids = {
    for k, e in var.eni_interfaces : k => concat(
      # Only look up keys that exist so the precondition below reports the bad key
      # instead of Terraform failing on an invalid index while evaluating this local.
      [for n in e.security_group_names : aws_security_group.this[n].id if contains(keys(var.security_groups), n)],
      tolist(e.security_group_ids)
    )
  }

  # Only resolve subnet names that exist so the precondition below reports the bad name
  # instead of Terraform failing on an invalid index while evaluating this local.
  eni_subnet_ids = {
    for k, e in var.eni_interfaces : k => aws_subnet.this[local.subnet_key_by_name[e.subnet][0]].id
    if contains(keys(local.subnet_key_by_name), e.subnet)
  }
}

resource "aws_network_interface" "this" {
  for_each = var.eni_interfaces

  subnet_id         = lookup(local.eni_subnet_ids, each.key, null)
  private_ips       = each.value.private_ips
  security_groups   = length(local.eni_security_group_ids[each.key]) > 0 ? local.eni_security_group_ids[each.key] : null
  source_dest_check = each.value.source_dest_check
  interface_type    = each.value.interface_type
  description       = each.value.description

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-eni" })

  lifecycle {
    precondition {
      condition     = contains(keys(local.subnet_key_by_name), each.value.subnet)
      error_message = "ENI ${each.key}: subnet \"${each.value.subnet}\" is not a subnet of this module (RSC-ENI-02)."
    }
    precondition {
      condition     = alltrue([for n in each.value.security_group_names : contains(keys(var.security_groups), n)])
      error_message = "ENI ${each.key}: security_group_names contains ${join(", ", [for n in each.value.security_group_names : "\"${n}\"" if !contains(keys(var.security_groups), n)])}, which is not a key of security_groups (RSC-ENI-05). Declared keys: ${join(", ", keys(var.security_groups))}. Use security_group_ids for security groups the caller created."
    }
  }
}
