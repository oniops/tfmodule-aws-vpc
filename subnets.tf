################################################################################
# Subnets (ARCHITECTURE 2.3, REQUIREMENTS 6.3, 6.4, RSC-VPCE-07). One resource for Shared Public,
# VPC Endpoint and stack subnets; the key prefix tells them apart.
################################################################################

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                          = aws_vpc.this.id
  availability_zone_id            = each.value.az
  cidr_block                      = each.value.cidr
  map_public_ip_on_launch         = false
  ipv6_cidr_block                 = var.enable_ipv6 && each.value.ipv6_index != null ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, each.value.ipv6_index) : null
  assign_ipv6_address_on_creation = var.enable_ipv6 && each.value.ipv6_index != null

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.value.name}-sn" })

  # Subnets in a secondary CIDR must be gone before the association is (RSC-VPC-03).
  depends_on = [aws_vpc_ipv4_cidr_block_association.this]
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.value.route_table].id

  lifecycle {
    precondition {
      condition     = contains(keys(var.route_tables), each.value.route_table)
      error_message = "Subnet ${each.key} points to route table \"${each.value.route_table}\" which is not declared in route_tables. Declared keys: ${join(", ", keys(var.route_tables))}."
    }
    precondition {
      condition     = each.value.group != "shared-public" || try(var.route_tables[each.value.route_table].routes["0.0.0.0/0"].gateway, null) == "igw"
      error_message = "Shared Public subnet ${each.key} must point to a route table whose 0.0.0.0/0 route targets gateway = \"igw\" (RSC-PUB-04)."
    }
    precondition {
      condition = each.value.group != "vpce" || (
        !contains(keys(try(var.route_tables[each.value.route_table].routes, {})), "0.0.0.0/0") &&
        !contains(keys(try(var.route_tables[each.value.route_table].routes, {})), "::/0")
      )
      error_message = "VPC Endpoint subnet ${each.key} must point to a route table without a default route (RSC-VPCE-07)."
    }
  }
}

################################################################################
# Subnet groups (RSC-SUB-05, RSC-SUB-09)
################################################################################

resource "aws_db_subnet_group" "this" {
  for_each = local.db_subnet_group

  name        = "${local.prefix}-${each.key}-sng"
  description = "DB subnet group ${each.key} of stack ${each.value.stack}"
  subnet_ids  = [for m in each.value.members : aws_subnet.this["${each.value.stack}/${m}"].id]

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-sng" })
}

resource "aws_elasticache_subnet_group" "this" {
  for_each = local.elasticache_subnet_group

  name        = "${local.prefix}-${each.key}-ecsng"
  description = "ElastiCache subnet group ${each.key} of stack ${each.value.stack}"
  subnet_ids  = [for m in each.value.members : aws_subnet.this["${each.value.stack}/${m}"].id]

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-ecsng" })
}

resource "aws_redshift_subnet_group" "this" {
  for_each = local.redshift_subnet_group

  name        = "${local.prefix}-${each.key}-rssng"
  description = "Redshift subnet group ${each.key} of stack ${each.value.stack}"
  subnet_ids  = [for m in each.value.members : aws_subnet.this["${each.value.stack}/${m}"].id]

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-rssng" })
}

resource "aws_memorydb_subnet_group" "this" {
  for_each = local.memorydb_subnet_group

  name        = "${local.prefix}-${each.key}-mdsng"
  description = "MemoryDB subnet group ${each.key} of stack ${each.value.stack}"
  subnet_ids  = [for m in each.value.members : aws_subnet.this["${each.value.stack}/${m}"].id]

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-mdsng" })
}
