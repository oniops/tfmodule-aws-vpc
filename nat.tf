################################################################################
# NAT Gateway and EIP (REQUIREMENTS 6.5)
################################################################################

resource "aws_eip" "nat" {
  for_each = { for k, n in var.nat_gateways : k => n if n.eip_allocation_id == null }

  domain = "vpc"
  tags   = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-eip" })
}

resource "aws_nat_gateway" "this" {
  for_each = var.nat_gateways

  allocation_id     = each.value.eip_allocation_id != null ? each.value.eip_allocation_id : aws_eip.nat[each.key].id
  subnet_id         = aws_subnet.this["shared-network/public/${each.value.public_subnet}"].id
  connectivity_type = "public"

  tags = merge(local.tags_base, each.value.tags, { Name = "${local.prefix}-${each.key}-nat" })

  lifecycle {
    precondition {
      condition     = var.shared_public != null && contains(keys(try(var.shared_public.subnets, {})), each.value.public_subnet)
      error_message = "NAT ${each.key}: public_subnet \"${each.value.public_subnet}\" is not a shared_public subnet (RSC-NAT-02)."
    }
  }

  depends_on = [aws_internet_gateway.this]
}
