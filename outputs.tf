################################################################################
# Outputs (ARCHITECTURE 9). Map outputs are keyed by the resource key; single
# resources that do not exist yield null.
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "VPC ARN"
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "Primary IPv4 CIDR of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "Amazon-provided IPv6 CIDR, null when enable_ipv6 is false"
  value       = var.enable_ipv6 ? aws_vpc.this.ipv6_cidr_block : null
}

output "vpc_owner_id" {
  description = "Account ID that owns the VPC"
  value       = aws_vpc.this.owner_id
}

output "vpc_secondary_cidr_association_ids" {
  description = "Secondary CIDR -> association ID"
  value       = { for k, a in aws_vpc_ipv4_cidr_block_association.this : k => a.id }
}

output "igw_id" {
  description = "Internet Gateway ID, null when no route targets igw"
  value       = one(aws_internet_gateway.this[*].id)
}

output "igw_arn" {
  description = "Internet Gateway ARN, null when no route targets igw"
  value       = one(aws_internet_gateway.this[*].arn)
}

output "eigw_id" {
  description = "Egress-only Internet Gateway ID, null when no route targets eigw"
  value       = one(aws_egress_only_internet_gateway.this[*].id)
}

output "default_security_group_id" {
  description = "Adopted default security group ID"
  value       = aws_default_security_group.this.id
}

output "default_network_acl_id" {
  description = "Adopted default network ACL ID"
  value       = aws_default_network_acl.this.id
}

output "default_route_table_id" {
  description = "Adopted default route table ID"
  value       = aws_default_route_table.this.id
}

output "dhcp_options_id" {
  description = "DHCP Options ID, null when dhcp_options is null"
  value       = one(aws_vpc_dhcp_options.this[*].id)
}

output "subnet_ids" {
  description = "Subnet key (shared-network/public/<name>, shared-network/vpce/<name>, <stack>/<name>) -> subnet ID"
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "subnet_arns" {
  description = "Subnet key -> subnet ARN"
  value       = { for k, s in aws_subnet.this : k => s.arn }
}

output "subnet_cidr_blocks" {
  description = "Subnet key -> IPv4 CIDR"
  value       = { for k, s in aws_subnet.this : k => s.cidr_block }
}

output "subnet_ipv6_cidr_blocks" {
  description = "Subnet key -> IPv6 CIDR (null for subnets without ipv6_index)"
  value       = { for k, s in aws_subnet.this : k => s.ipv6_cidr_block }
}

output "shared_network" {
  description = "Convenience view of Shared Network subnets keyed by subnet name"
  value = {
    public_subnet_ids         = { for k, s in local.shared_public_subnets : s.name => aws_subnet.this[k].id }
    public_subnet_arns        = { for k, s in local.shared_public_subnets : s.name => aws_subnet.this[k].arn }
    public_subnet_cidr_blocks = { for k, s in local.shared_public_subnets : s.name => aws_subnet.this[k].cidr_block }
    vpce_subnet_ids           = { for k, s in local.vpce_subnets : s.name => aws_subnet.this[k].id }
    vpce_subnet_arns          = { for k, s in local.vpce_subnets : s.name => aws_subnet.this[k].arn }
    vpce_subnet_cidr_blocks   = { for k, s in local.vpce_subnets : s.name => aws_subnet.this[k].cidr_block }
  }
}

output "nat_gateway_ids" {
  description = "NAT key -> NAT Gateway ID"
  value       = { for k, n in aws_nat_gateway.this : k => n.id }
}

output "nat_eip_allocation_ids" {
  description = "NAT key -> EIP allocation ID (created or reused)"
  value       = { for k, n in aws_nat_gateway.this : k => n.allocation_id }
}

output "nat_public_ips" {
  description = "NAT key -> public IP"
  value       = { for k, n in aws_nat_gateway.this : k => n.public_ip }
}

output "eni_ids" {
  description = "ENI key -> network interface ID"
  value       = { for k, e in aws_network_interface.this : k => e.id }
}

output "eni_arns" {
  description = "ENI key -> network interface ARN"
  value       = { for k, e in aws_network_interface.this : k => e.arn }
}

output "eni_private_ips" {
  description = "ENI key -> primary private IP"
  value       = { for k, e in aws_network_interface.this : k => e.private_ip }
}

output "security_group_ids" {
  description = "Security group key -> ID (module-created groups; not the endpoint SG)"
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}

output "security_group_arns" {
  description = "Security group key -> ARN"
  value       = { for k, sg in aws_security_group.this : k => sg.arn }
}

output "route_table_ids" {
  description = "Route table key -> ID. Pass these to the peering module to add routes"
  value       = { for k, rt in aws_route_table.this : k => rt.id }
}

output "route_table_association_ids" {
  description = "Subnet key -> route table association ID"
  value       = { for k, a in aws_route_table_association.this : k => a.id }
}

output "network_acl_ids" {
  description = "NACL key (<stack> or shared-network/public) -> ID"
  value       = { for k, n in aws_network_acl.this : k => n.id }
}

output "network_acl_arns" {
  description = "NACL key -> ARN"
  value       = { for k, n in aws_network_acl.this : k => n.arn }
}

output "stacks" {
  description = "Per-stack convenience view keyed by stack, then by subnet name or subnet group name (db, elasticache, redshift, memorydb)"
  value = {
    for stack in keys(var.stack_subnets) : stack => {
      subnet_ids                     = { for k, s in local.stack_subnets : s.name => aws_subnet.this[k].id if s.stack == stack }
      db_subnet_group_names          = { for g, v in local.db_subnet_group : g => aws_db_subnet_group.this[g].name if v.stack == stack }
      db_subnet_group_arns           = { for g, v in local.db_subnet_group : g => aws_db_subnet_group.this[g].arn if v.stack == stack }
      elasticache_subnet_group_names = { for g, v in local.elasticache_subnet_group : g => aws_elasticache_subnet_group.this[g].name if v.stack == stack }
      elasticache_subnet_group_arns  = { for g, v in local.elasticache_subnet_group : g => aws_elasticache_subnet_group.this[g].arn if v.stack == stack }
      redshift_subnet_group_names    = { for g, v in local.redshift_subnet_group : g => aws_redshift_subnet_group.this[g].name if v.stack == stack }
      redshift_subnet_group_arns     = { for g, v in local.redshift_subnet_group : g => aws_redshift_subnet_group.this[g].arn if v.stack == stack }
      memorydb_subnet_group_names    = { for g, v in local.memorydb_subnet_group : g => aws_memorydb_subnet_group.this[g].name if v.stack == stack }
      memorydb_subnet_group_arns     = { for g, v in local.memorydb_subnet_group : g => aws_memorydb_subnet_group.this[g].arn if v.stack == stack }
    }
  }
}

output "vpc_endpoint_ids" {
  description = "Service -> VPC Endpoint ID (gateway and interface)"
  value       = merge({ for k, e in aws_vpc_endpoint.gateway : k => e.id }, { for k, e in aws_vpc_endpoint.interface : k => e.id })
}

output "vpc_endpoint_dns_entries" {
  description = "Service -> DNS entries of the endpoint"
  value       = merge({ for k, e in aws_vpc_endpoint.gateway : k => e.dns_entry }, { for k, e in aws_vpc_endpoint.interface : k => e.dns_entry })
}

output "vpc_endpoint_security_group_id" {
  description = "Endpoint security group ID created by the module, null when every Interface Endpoint names its own SG"
  value       = one(aws_security_group.vpce[*].id)
}

output "vgw_id" {
  description = "Virtual Private Gateway ID (created or existing), null when vpn_gateway is null"
  value       = local.vgw_id
}

output "vgw_arn" {
  description = "Virtual Private Gateway ARN, null when not created by this module"
  value       = one(aws_vpn_gateway.this[*].arn)
}

output "vgw_attachment_id" {
  description = "VGW attachment ID when an existing VGW is attached, otherwise null"
  value       = one(aws_vpn_gateway_attachment.this[*].id)
}

output "cgw_ids" {
  description = "Customer gateway key -> ID"
  value       = { for k, c in aws_customer_gateway.this : k => c.id }
}

output "cgw_arns" {
  description = "Customer gateway key -> ARN"
  value       = { for k, c in aws_customer_gateway.this : k => c.arn }
}

output "flow_log_ids" {
  description = "Flow Log destination key -> Flow Log ID"
  value       = { for k, f in aws_flow_log.this : k => f.id }
}

output "flow_log_arns" {
  description = "Flow Log destination key -> Flow Log ARN"
  value       = { for k, f in aws_flow_log.this : k => f.arn }
}

output "flow_log_destination_arns" {
  description = "Flow Log destination key -> the destination ARN the flow log writes to"
  value       = { for k, f in aws_flow_log.this : k => f.log_destination }
}

output "private_zone_id" {
  description = "Private Hosted Zone ID, null when private_dns is null"
  value       = one(aws_route53_zone.private[*].zone_id)
}

output "private_zone_name" {
  description = "Private Hosted Zone name"
  value       = one(aws_route53_zone.private[*].name)
}

output "private_zone_arn" {
  description = "Private Hosted Zone ARN"
  value       = one(aws_route53_zone.private[*].arn)
}
