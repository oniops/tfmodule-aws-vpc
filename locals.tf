# Locals only flatten nested inputs into for_each maps and precompute checks. No input
# value is transformed on the way to a resource argument (ARCHITECTURE 12.3).
locals {
  prefix    = var.context.name_prefix
  tags_base = merge(var.context.tags, var.tags)

  shared_public_nacl_key = "shared-network/public"

  ################################################################################
  # Subnets. Resource key -> subnet entry (ARCHITECTURE 6, 2.3).
  ################################################################################
  shared_public_subnets = var.shared_public == null ? {} : {
    for name, s in var.shared_public.subnets : "shared-network/public/${name}" => {
      name        = name
      group       = "shared-public"
      stack       = null
      az          = s.az
      cidr        = s.cidr
      route_table = s.route_table
      ipv6_index  = s.ipv6_index
      tags        = merge(var.shared_public.tags, s.tags)
      nacl        = var.shared_public.nacl == null ? null : local.shared_public_nacl_key
    }
  }

  vpce_subnets = {
    for name, s in var.vpc_endpoint_subnets : "shared-network/vpce/${name}" => {
      name        = name
      group       = "vpce"
      stack       = null
      az          = s.az
      cidr        = s.cidr
      route_table = s.route_table
      ipv6_index  = s.ipv6_index
      tags        = s.tags
      nacl        = null
    }
  }

  stack_subnets = merge([
    for stack, st in var.stack_subnets : {
      for name, s in st.subnets : "${stack}/${name}" => {
        name        = name
        group       = "stack"
        stack       = stack
        az          = s.az
        cidr        = s.cidr
        route_table = s.route_table
        ipv6_index  = s.ipv6_index
        tags        = merge(st.tags, s.tags)
        nacl        = st.nacl == null ? null : stack
      }
    }
  ]...)

  subnets = merge(local.shared_public_subnets, local.vpce_subnets, local.stack_subnets)
  # Grouped so a duplicated subnet name does not abort this local; the aws_vpc precondition
  # must be the thing that reports it (ARCHITECTURE 9.2.2). Consumers take element 0.
  subnet_key_by_name = { for k, s in local.subnets : s.name => k... }
  subnet_ipv6_index  = [for s in local.subnets : s.ipv6_index if s.ipv6_index != null]

  ################################################################################
  # Routes. Key <rt_key>/<destination> (RSC-RT-04).
  ################################################################################
  routes = {
    for r in flatten([
      for rt, t in var.route_tables : [
        for dest, tgt in t.routes : { key = "${rt}/${dest}", rt = rt, dest = dest, tgt = tgt }
      ]
    ]) : r.key => r
  }
  igw_routes  = [for r in local.routes : r.key if r.tgt.gateway == "igw"]
  eigw_routes = [for r in local.routes : r.key if r.tgt.gateway == "eigw"]

  ################################################################################
  # NACLs. Key <stack> or shared-network/public (RSC-NACL-01).
  ################################################################################
  nacls = merge(
    var.shared_public == null || try(var.shared_public.nacl, null) == null ? {} : {
      (local.shared_public_nacl_key) = { name = "shared-public", rules = var.shared_public.nacl, tags = var.shared_public.tags }
    },
    { for stack, st in var.stack_subnets : stack => { name = stack, rules = st.nacl, tags = st.tags } if st.nacl != null }
  )
  nacl_rules = {
    for r in flatten([
      for nk, n in local.nacls : [
        for dir in ["ingress", "egress"] : [
          for name, rule in n.rules[dir] : { key = "${nk}/${dir}/${name}", nacl = nk, egress = dir == "egress", rule = rule }
        ]
      ]
    ]) : r.key => r
  }

  ################################################################################
  # Security group rules. Key <sg_key>/<direction>/<rule_name> (RSC-SG-03).
  ################################################################################
  sg_rules = {
    for r in flatten([
      for sk, sg in var.security_groups : [
        for dir in ["ingress", "egress"] : [
          for name, rule in sg[dir] : { key = "${sk}/${dir}/${name}", sg = sk, dir = dir, rule = rule }
        ]
      ]
    ]) : r.key => r
  }
  sg_ingress_rules = { for k, r in local.sg_rules : k => r if r.dir == "ingress" }
  sg_egress_rules  = { for k, r in local.sg_rules : k => r if r.dir == "egress" }

  ################################################################################
  # Subnet groups. Key <group> (unique across stacks by validation).
  ################################################################################
  db_subnet_group = merge([
    for stack, st in var.stack_subnets : {
      for g, members in st.db_subnet_group : g => { stack = stack, members = members, tags = st.tags }
    }
  ]...)
  elasticache_subnet_group = merge([
    for stack, st in var.stack_subnets : {
      for g, members in st.elasticache_subnet_group : g => { stack = stack, members = members, tags = st.tags }
    }
  ]...)
  redshift_subnet_group = merge([
    for stack, st in var.stack_subnets : {
      for g, members in st.redshift_subnet_group : g => { stack = stack, members = members, tags = st.tags }
    }
  ]...)
  memorydb_subnet_group = merge([
    for stack, st in var.stack_subnets : {
      for g, members in st.memorydb_subnet_group : g => { stack = stack, members = members, tags = st.tags }
    }
  ]...)

  ################################################################################
  # VPC Endpoints.
  ################################################################################
  gateway_endpoint_rts = {
    for p in setproduct(var.vpc_endpoints.gateway, keys(var.route_tables)) : "${p[0]}/${p[1]}" => { service = p[0], rt = p[1] }
  }

  ################################################################################
  # IPv4 CIDR arithmetic for the VPC-wide checks (ARCHITECTURE 9.1, P-02).
  # Terraform 1.5 has no cidrcontains(); ranges are compared as integers.
  ################################################################################
  vpc_cidrs = concat([var.vpc_cidr], tolist(var.secondary_cidrs))
  all_cidrs = distinct(concat(local.vpc_cidrs, [for s in local.subnets : s.cidr]))
  cidr_start = {
    for c in local.all_cidrs : c => sum([for i, o in split(".", cidrhost(c, 0)) : tonumber(o) * pow(256, 3 - i)])
  }
  cidr_end = {
    for c in local.all_cidrs : c => local.cidr_start[c] + pow(2, 32 - tonumber(split("/", c)[1])) - 1
  }
  subnet_keys = keys(local.subnets)
  subnets_outside_vpc = [
    for k, s in local.subnets : k
    if !anytrue([for v in local.vpc_cidrs : local.cidr_start[s.cidr] >= local.cidr_start[v] && local.cidr_end[s.cidr] <= local.cidr_end[v]])
  ]
  subnet_overlaps = flatten([
    for i, a in local.subnet_keys : [
      for j, b in local.subnet_keys : "${a} <-> ${b}"
      if j > i &&
      local.cidr_start[local.subnets[a].cidr] <= local.cidr_end[local.subnets[b].cidr] &&
      local.cidr_start[local.subnets[b].cidr] <= local.cidr_end[local.subnets[a].cidr]
    ]
  ])
}
