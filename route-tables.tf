################################################################################
# Route Tables, Routes, VGW propagation, Gateway Endpoint attachment (REQUIREMENTS 6.7)
################################################################################

resource "aws_route_table" "this" {
  for_each = var.route_tables

  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-rt" })
}

locals {
  # Gateway targets the module owns, looked up by the route's gateway value.
  gateway_ids = {
    igw = one(aws_internet_gateway.this[*].id)
    vgw = local.vgw_id
  }
}

# Every route is its own resource so other modules can add routes to these tables
# without changing this module's plan (RSC-RT-02).
resource "aws_route" "this" {
  for_each = local.routes

  route_table_id              = aws_route_table.this[each.value.rt].id
  destination_cidr_block      = strcontains(each.value.dest, ":") ? null : each.value.dest
  destination_ipv6_cidr_block = strcontains(each.value.dest, ":") ? each.value.dest : null

  # Guard on the field itself so a route without a gateway target keeps a known null at plan
  # time; looking the value up in a map whose entries are still unknown would hide that.
  gateway_id             = each.value.tgt.gateway == null ? null : lookup(local.gateway_ids, each.value.tgt.gateway, null)
  egress_only_gateway_id = each.value.tgt.gateway == "eigw" ? one(aws_egress_only_internet_gateway.this[*].id) : null
  nat_gateway_id         = each.value.tgt.nat_gateway == null ? null : aws_nat_gateway.this[each.value.tgt.nat_gateway].id
  network_interface_id   = each.value.tgt.eni != null ? aws_network_interface.this[each.value.tgt.eni].id : each.value.tgt.network_interface_id

  timeouts {
    create = "5m"
  }

  lifecycle {
    precondition {
      condition     = each.value.tgt.nat_gateway == null ? true : contains(keys(var.nat_gateways), each.value.tgt.nat_gateway)
      error_message = "Route ${each.key} targets a nat_gateway key that is not declared in nat_gateways."
    }
    precondition {
      condition     = each.value.tgt.eni == null ? true : contains(keys(var.eni_interfaces), each.value.tgt.eni)
      error_message = "Route ${each.key} targets an eni key that is not declared in eni_interfaces."
    }
    precondition {
      condition     = !contains(local.vpc_cidrs, each.value.dest)
      error_message = "Route ${each.key}: the destination equals a VPC CIDR; the local route is managed by AWS (RSC-RT-01)."
    }
    precondition {
      condition     = each.value.tgt.gateway != "vgw" || var.vpn_gateway != null
      error_message = "Route ${each.key} targets gateway = \"vgw\" but vpn_gateway is null."
    }
    precondition {
      condition     = var.enable_ipv6 || (!strcontains(each.value.dest, ":") && each.value.tgt.gateway != "eigw")
      error_message = "Route ${each.key} is IPv6 (destination or eigw) but enable_ipv6 is false."
    }
  }
}

resource "aws_vpn_gateway_route_propagation" "this" {
  for_each = { for k, rt in var.route_tables : k => rt if rt.propagate_vgw }

  route_table_id = aws_route_table.this[each.key].id
  vpn_gateway_id = local.vgw_id

  lifecycle {
    precondition {
      condition     = var.vpn_gateway != null
      error_message = "Route table ${each.key} sets propagate_vgw = true but vpn_gateway is null."
    }
  }
}

# Gateway Endpoints attach to every route table (RSC-RT-06).
resource "aws_vpc_endpoint_route_table_association" "this" {
  for_each = local.gateway_endpoint_rts

  vpc_endpoint_id = aws_vpc_endpoint.gateway[each.value.service].id
  route_table_id  = aws_route_table.this[each.value.rt].id
}
