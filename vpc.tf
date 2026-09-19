################################################################################
# VPC (RSC-VPC-01..05). VPC-wide input checks that need more than one variable
# are gathered here as preconditions and evaluated once (POLICIES 6.2.2).
################################################################################

resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = var.enable_ipv6
  enable_dns_support               = true
  enable_dns_hostnames             = true
  instance_tenancy                 = "default"

  tags = merge(local.tags_base, { Name = "${local.prefix}-vpc" })

  lifecycle {
    precondition {
      condition     = length(distinct([for s in local.subnets : s.name])) == length(local.subnets)
      error_message = "Subnet names must be unique across shared_public, vpc_endpoint_subnets and every stack."
    }
    precondition {
      condition     = length(local.subnets_outside_vpc) == 0
      error_message = "Subnet CIDRs must lie inside vpc_cidr or secondary_cidrs. Outside: ${join(", ", local.subnets_outside_vpc)}."
    }
    precondition {
      condition     = length(local.subnet_overlaps) == 0
      error_message = "Subnet CIDRs must not overlap. Overlapping: ${join(", ", local.subnet_overlaps)}."
    }
    precondition {
      condition     = length(distinct([for s in local.subnets : s.az])) >= 2
      error_message = "Subnets must span at least two distinct AZ IDs (ARCHITECTURE 2.1)."
    }
    precondition {
      condition     = length(distinct(local.subnet_ipv6_index)) == length(local.subnet_ipv6_index)
      error_message = "ipv6_index must be unique across the VPC."
    }
    precondition {
      condition     = var.enable_ipv6 || length(local.subnet_ipv6_index) == 0
      error_message = "ipv6_index is set on a subnet but enable_ipv6 is false."
    }
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  for_each = var.secondary_cidrs

  vpc_id     = aws_vpc.this.id
  cidr_block = each.value
}

################################################################################
# Internet gateways. Derived from route targets (RSC-PUB-05, RSC-RT-05).
################################################################################

resource "aws_internet_gateway" "this" {
  count = length(local.igw_routes) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags_base, { Name = "${local.prefix}-igw" })
}

resource "aws_egress_only_internet_gateway" "this" {
  count = length(local.eigw_routes) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags_base, { Name = "${local.prefix}-eigw" })
}

################################################################################
# Default resources are always adopted (RSC-DEF-01..03).
################################################################################

# No ingress/egress blocks: the provider revokes every rule, so the default SG blocks all traffic.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags_base, { Name = "${local.prefix}-default-sg" })
}

resource "aws_default_route_table" "this" {
  default_route_table_id = aws_vpc.this.default_route_table_id
  tags                   = merge(local.tags_base, { Name = "${local.prefix}-default-rt" })
}

# Keeps the AWS default allow-all rules (100 IPv4, 101 IPv6) in both directions.
resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    rule_no         = 101
    action          = "allow"
    protocol        = "-1"
    ipv6_cidr_block = "::/0"
    from_port       = 0
    to_port         = 0
  }
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    rule_no         = 101
    action          = "allow"
    protocol        = "-1"
    ipv6_cidr_block = "::/0"
    from_port       = 0
    to_port         = 0
  }

  tags = merge(local.tags_base, { Name = "${local.prefix}-default-nacl" })

  # Subnets without a dedicated NACL fall back here; AWS manages that membership.
  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

################################################################################
# DHCP Options (RSC-DEF-04)
################################################################################

resource "aws_vpc_dhcp_options" "this" {
  count = var.dhcp_options != null ? 1 : 0

  domain_name          = var.dhcp_options.domain_name != null ? var.dhcp_options.domain_name : var.context.pri_domain
  domain_name_servers  = var.dhcp_options.domain_name_servers
  ntp_servers          = var.dhcp_options.ntp_servers
  netbios_name_servers = var.dhcp_options.netbios_name_servers
  netbios_node_type    = var.dhcp_options.netbios_node_type

  tags = merge(local.tags_base, { Name = "${local.prefix}-dhcp" })

  lifecycle {
    precondition {
      condition     = var.dhcp_options.domain_name != null || var.context.pri_domain != null
      error_message = "dhcp_options.domain_name is omitted and context.pri_domain is null."
    }
  }
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.dhcp_options != null ? 1 : 0

  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}
