################################################################################
# VPC
################################################################################

variable "vpc_cidr" {
  type        = string
  description = "Primary IPv4 CIDR of the VPC. Changing it recreates the VPC."

  # Checked here so a malformed value fails with this message instead of an internal
  # error from the CIDR arithmetic in locals.tf (ARCHITECTURE 9.1).
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && !strcontains(var.vpc_cidr, ":")
    error_message = "vpc_cidr must be a valid IPv4 CIDR such as 10.230.0.0/16."
  }
}

variable "secondary_cidrs" {
  type        = set(string)
  default     = []
  description = "Secondary IPv4 CIDRs associated with the VPC. Each entry becomes one aws_vpc_ipv4_cidr_block_association keyed by the CIDR string."

  validation {
    condition     = alltrue([for c in var.secondary_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "secondary_cidrs entries must be valid IPv4 CIDRs such as 100.64.0.0/16. Invalid: ${join(", ", [for c in var.secondary_cidrs : c if !(can(cidrhost(c, 0)) && !strcontains(c, ":"))])}."
  }
}

variable "enable_ipv6" {
  type        = bool
  default     = false
  description = "Assign an Amazon-provided IPv6 /56 to the VPC. When false, every IPv6 input (subnet ipv6_index, IPv6 routes, ipv6_cidr_block NACL rules) fails at plan time."
}

################################################################################
# Shared Public Network
################################################################################

variable "shared_public" {
  # Field order follows the reading order of the input: what tags everything, what is
  # created, then the optional NACL that guards it (DEC-104).
  type = object({
    tags = optional(map(string), {})
    subnets = map(object({
      az          = string
      cidr        = string
      route_table = string
      ipv6_index  = optional(number)
      tags        = optional(map(string), {})
    }))
    nacl = optional(object({
      ingress = optional(map(object({
        rule_number     = number
        rule_action     = string
        protocol        = string
        from_port       = optional(number)
        to_port         = optional(number)
        cidr_block      = optional(string)
        ipv6_cidr_block = optional(string)
        icmp_type       = optional(number)
        icmp_code       = optional(number)
      })), {})
      egress = optional(map(object({
        rule_number     = number
        rule_action     = string
        protocol        = string
        from_port       = optional(number)
        to_port         = optional(number)
        cidr_block      = optional(string)
        ipv6_cidr_block = optional(string)
        icmp_type       = optional(number)
        icmp_code       = optional(number)
      })), {})
    }), null)
  })
  default     = null
  description = <<-EOF
Shared Public Network shared by every stack for NAT Gateways and Internet-facing load
balancers. subnets is a flat map keyed by subnet name; each entry carries its AZ ID, CIDR
and the route_tables key it is associated with. Every subnet here must point to a route
table whose 0.0.0.0/0 route targets the Internet Gateway. tags apply to all subnets below
and to the Shared Public NACL; nacl is optional and, when omitted, the subnets use the
default NACL. When enable_ipv6 is true, every cidr_block rule of that NACL needs a matching
ipv6_cidr_block rule: the module never derives one, and without it all IPv6 traffic to these
subnets is dropped. Subnet name and az/cidr changes recreate the subnet; route_table changes
only replace the association.

  shared_public = {
    tags = { Tier = "public" }
    subnets = {
      pub-a1 = { az = "apne2-az1", cidr = "10.230.0.0/24", route_table = "pub" }
      pub-c1 = { az = "apne2-az3", cidr = "10.230.1.0/24", route_table = "pub" }
    }
  }
EOF

  validation {
    condition     = var.shared_public == null ? true : length(var.shared_public.subnets) > 0
    error_message = "shared_public.subnets must contain at least one subnet. Omit shared_public entirely to create none."
  }
  validation {
    condition = var.shared_public == null ? true : alltrue([
      for k, s in var.shared_public.subnets : can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az))
    ])
    error_message = "Subnet names may contain only lowercase letters, digits and '-'; az must be an AZ ID ending in -az<n>. Offending shared_public.subnets: ${join(", ", var.shared_public == null ? [] : [for k, s in var.shared_public.subnets : k if !(can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az)))])}."
  }
  validation {
    condition = var.shared_public == null ? true : alltrue([
      for s in var.shared_public.subnets : can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":")
    ])
    error_message = "cidr must be a valid IPv4 CIDR such as 10.230.0.0/24. Offending shared_public.subnets: ${join(", ", var.shared_public == null ? [] : [for k, s in var.shared_public.subnets : k if !(can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":"))])}."
  }
  validation {
    condition = var.shared_public == null ? true : alltrue([
      for s in var.shared_public.subnets : s.ipv6_index == null ? true : (s.ipv6_index >= 0 && s.ipv6_index <= 255)
    ])
    error_message = "ipv6_index must be between 0 and 255. Offending shared_public.subnets: ${join(", ", var.shared_public == null ? [] : [for k, s in var.shared_public.subnets : k if s.ipv6_index == null ? false : !(s.ipv6_index >= 0 && s.ipv6_index <= 255)])}."
  }
  validation {
    condition = var.shared_public == null ? true : (
      !contains(keys(var.shared_public.tags), "Name") &&
      alltrue([for s in var.shared_public.subnets : !contains(keys(s.tags), "Name")])
    )
    error_message = "tags must not contain the protected key \"Name\": the module sets it from the naming rule. Offending: ${join(", ", var.shared_public == null ? [] : concat(contains(keys(var.shared_public.tags), "Name") ? ["shared_public.tags"] : [], [for k, s in var.shared_public.subnets : "shared_public.subnets.${k}.tags" if contains(keys(s.tags), "Name")]))}."
  }
  # The NACL rule checks are split so the message can name the rule that failed and the
  # reason it failed. All three implement V-21 and V-23 (ARCHITECTURE 9.2.1).
  validation {
    condition = try(var.shared_public.nacl, null) == null ? true : alltrue(flatten([
      for dir in ["ingress", "egress"] : [
        for name, r in var.shared_public.nacl[dir] :
        can(regex("^[a-z0-9-]+$", name)) &&
        contains(["allow", "deny"], r.rule_action) &&
        r.rule_number >= 1 && r.rule_number <= 32766
      ]
    ]))
    error_message = "Shared Public NACL rule: names may contain only lowercase letters, digits and '-', rule_action must be allow|deny and rule_number must be 1-32766. Offending rules: ${join(", ", try(var.shared_public.nacl, null) == null ? [] : flatten([for dir in ["ingress", "egress"] : [for name, r in var.shared_public.nacl[dir] : "${dir}/${name}" if !(can(regex("^[a-z0-9-]+$", name)) && contains(["allow", "deny"], r.rule_action) && r.rule_number >= 1 && r.rule_number <= 32766)]]))}."
  }
  validation {
    condition = try(var.shared_public.nacl, null) == null ? true : alltrue(flatten([
      for dir in ["ingress", "egress"] : [
        for name, r in var.shared_public.nacl[dir] :
        contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.protocol) &&
        (!contains(["tcp", "udp", "6", "17"], r.protocol) || (r.from_port != null && r.to_port != null)) &&
        (!contains(["icmp", "icmpv6", "1", "58"], r.protocol) || (r.icmp_type != null && r.icmp_code != null)) &&
        (r.protocol != "-1" || (r.from_port == null && r.to_port == null && r.icmp_type == null && r.icmp_code == null))
      ]
    ]))
    error_message = "Shared Public NACL rule: protocol must be -1|tcp|udp|icmp|icmpv6 or 6|17|1|58, tcp/udp need from_port and to_port, icmp/icmpv6 need icmp_type and icmp_code, and -1 takes no ports. Offending rules: ${join(", ", try(var.shared_public.nacl, null) == null ? [] : flatten([for dir in ["ingress", "egress"] : [for name, r in var.shared_public.nacl[dir] : "${dir}/${name}" if !(contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.protocol) && (!contains(["tcp", "udp", "6", "17"], r.protocol) || (r.from_port != null && r.to_port != null)) && (!contains(["icmp", "icmpv6", "1", "58"], r.protocol) || (r.icmp_type != null && r.icmp_code != null)) && (r.protocol != "-1" || (r.from_port == null && r.to_port == null && r.icmp_type == null && r.icmp_code == null)))]]))}."
  }
  validation {
    condition = try(var.shared_public.nacl, null) == null ? true : alltrue(flatten([
      for dir in ["ingress", "egress"] : [
        for name, r in var.shared_public.nacl[dir] :
        ((r.cidr_block != null) != (r.ipv6_cidr_block != null)) &&
        (r.ipv6_cidr_block == null ? true : (r.ipv6_cidr_block == "vpc" ? true : (strcontains(r.ipv6_cidr_block, ":") && can(cidrhost(r.ipv6_cidr_block, 0)))))
      ]
    ]))
    error_message = "Shared Public NACL rule: set exactly one of cidr_block and ipv6_cidr_block, and ipv6_cidr_block must be an IPv6 CIDR or the reserved value \"vpc\". Offending rules: ${join(", ", try(var.shared_public.nacl, null) == null ? [] : flatten([for dir in ["ingress", "egress"] : [for name, r in var.shared_public.nacl[dir] : "${dir}/${name}" if !(((r.cidr_block != null) != (r.ipv6_cidr_block != null)) && (r.ipv6_cidr_block == null ? true : (r.ipv6_cidr_block == "vpc" ? true : (strcontains(r.ipv6_cidr_block, ":") && can(cidrhost(r.ipv6_cidr_block, 0))))))]]))}."
  }
  validation {
    condition = try(var.shared_public.nacl, null) == null ? true : alltrue([
      for dir in ["ingress", "egress"] :
      length(distinct([for r in var.shared_public.nacl[dir] : r.rule_number])) == length(var.shared_public.nacl[dir])
    ])
    error_message = "Shared Public NACL rule_number must be unique within a direction. Offending directions: ${join(", ", try(var.shared_public.nacl, null) == null ? [] : [for dir in ["ingress", "egress"] : dir if length(distinct([for r in var.shared_public.nacl[dir] : r.rule_number])) != length(var.shared_public.nacl[dir])])}."
  }
}

variable "vpc_endpoint_subnets" {
  type = map(object({
    az          = string
    cidr        = string
    route_table = string
    ipv6_index  = optional(number)
    tags        = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOF
Subnets dedicated to Interface VPC Endpoint ENIs, keyed by subnet name. Each subnet must
point to a route table without a default route (0.0.0.0/0 or ::/0) and at most one subnet
may be declared per AZ. Workloads are never placed here; declare them as stacks instead.
Changing a subnet name, az or cidr recreates the subnet; a route_table change only replaces
the association.

  vpc_endpoint_subnets = {
    vpce-a1 = { az = "apne2-az1", cidr = "10.230.4.0/26",  route_table = "iso" }
    vpce-c1 = { az = "apne2-az3", cidr = "10.230.4.64/26", route_table = "iso" }
  }
EOF

  validation {
    condition = alltrue([
      for k, s in var.vpc_endpoint_subnets : can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az))
    ])
    error_message = "Subnet names may contain only lowercase letters, digits and '-'; az must be an AZ ID ending in -az<n>. Offending vpc_endpoint_subnets: ${join(", ", [for k, s in var.vpc_endpoint_subnets : k if !(can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az)))])}."
  }
  validation {
    condition     = alltrue([for s in var.vpc_endpoint_subnets : can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":")])
    error_message = "cidr must be a valid IPv4 CIDR such as 10.230.0.0/24. Offending vpc_endpoint_subnets: ${join(", ", [for k, s in var.vpc_endpoint_subnets : k if !(can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":"))])}."
  }
  validation {
    condition     = alltrue([for s in var.vpc_endpoint_subnets : s.ipv6_index == null ? true : (s.ipv6_index >= 0 && s.ipv6_index <= 255)])
    error_message = "ipv6_index must be between 0 and 255. Offending vpc_endpoint_subnets: ${join(", ", [for k, s in var.vpc_endpoint_subnets : k if s.ipv6_index == null ? false : !(s.ipv6_index >= 0 && s.ipv6_index <= 255)])}."
  }
  validation {
    condition     = length(distinct([for s in var.vpc_endpoint_subnets : s.az])) == length(var.vpc_endpoint_subnets)
    error_message = "vpc_endpoint_subnets may contain at most one subnet per AZ; an Interface Endpoint places one ENI per subnet. Duplicated AZ IDs: ${join(", ", distinct([for k, s in var.vpc_endpoint_subnets : s.az if length([for k2, s2 in var.vpc_endpoint_subnets : k2 if s2.az == s.az]) > 1]))}."
  }
  validation {
    condition     = alltrue([for s in var.vpc_endpoint_subnets : !contains(keys(s.tags), "Name")])
    error_message = "tags must not contain the protected key \"Name\": the module sets it from the naming rule. Offending vpc_endpoint_subnets: ${join(", ", [for k, s in var.vpc_endpoint_subnets : k if contains(keys(s.tags), "Name")])}."
  }
}

################################################################################
# Workload stacks
################################################################################

variable "stack_subnets" {
  # Field order follows the reading order of the input: what tags the stack, what subnets
  # it owns, the optional NACL that guards them, then the subnet groups built from them
  # (DEC-104).
  type = map(object({
    tags = optional(map(string), {})
    subnets = map(object({
      az          = string
      cidr        = string
      route_table = string
      ipv6_index  = optional(number)
      tags        = optional(map(string), {})
    }))
    nacl = optional(object({
      ingress = optional(map(object({
        rule_number     = number
        rule_action     = string
        protocol        = string
        from_port       = optional(number)
        to_port         = optional(number)
        cidr_block      = optional(string)
        ipv6_cidr_block = optional(string)
        icmp_type       = optional(number)
        icmp_code       = optional(number)
      })), {})
      egress = optional(map(object({
        rule_number     = number
        rule_action     = string
        protocol        = string
        from_port       = optional(number)
        to_port         = optional(number)
        cidr_block      = optional(string)
        ipv6_cidr_block = optional(string)
        icmp_type       = optional(number)
        icmp_code       = optional(number)
      })), {})
    }), null)
    db_subnet_group          = optional(map(set(string)), {})
    elasticache_subnet_group = optional(map(set(string)), {})
    redshift_subnet_group    = optional(map(set(string)), {})
    memorydb_subnet_group    = optional(map(set(string)), {})
  }))
  default     = {}
  description = <<-EOF
Workload stacks keyed by stack name. Each stack owns a flat map of subnets keyed by subnet
name (no role layer): the tier is expressed by the name and the character by the route
table the subnet points to. Stack tags apply to every subnet, the stack NACL and the subnet
groups of that stack; subnet tags apply to one subnet only. nacl is one NACL per stack.
db_subnet_group, elasticache_subnet_group, redshift_subnet_group and memorydb_subnet_group
map a group name to the subnet names it contains; members must belong to the same stack and
group names must be unique across stacks within the same group type. One subnet may belong
to groups of different types. A DB subnet group needs members in at least two AZs; the other
three need at least one member, and their Multi-AZ deployments need two AZs as well. Stack
keys must not start with "shared-". Subnet names must be unique across the whole VPC.
When enable_ipv6 is true, every cidr_block rule of a stack NACL needs a matching
ipv6_cidr_block rule, otherwise all IPv6 traffic to that stack is dropped. Changing a stack
key or a subnet name, az or cidr recreates those subnets; a route_table change only replaces
the association.

  stack_subnets = {
    web = {
      tags = { Stack = "web" }
      subnets = {
        app-a1  = { az = "apne2-az1", cidr = "10.230.30.0/24", route_table = "pri-a1" }
        app-c1  = { az = "apne2-az3", cidr = "10.230.31.0/24", route_table = "pri-c1" }
        data-a1 = { az = "apne2-az1", cidr = "10.230.40.0/24", route_table = "iso" }
        data-c1 = { az = "apne2-az3", cidr = "10.230.42.0/24", route_table = "iso" }
      }
      db_subnet_group       = { data = ["data-a1", "data-c1"] }
      memorydb_subnet_group = { cache = ["data-a1", "data-c1"] }
    }
  }
EOF

  validation {
    condition     = alltrue([for k, st in var.stack_subnets : can(regex("^[a-z0-9-]+$", k)) && !startswith(k, "shared-")])
    error_message = "Stack keys may contain only lowercase letters, digits and '-' and must not start with \"shared-\", which is reserved for Shared Network resources. Offending stacks: ${join(", ", [for k, st in var.stack_subnets : k if !(can(regex("^[a-z0-9-]+$", k)) && !startswith(k, "shared-"))])}."
  }
  validation {
    condition     = alltrue([for st in var.stack_subnets : length(st.subnets) > 0])
    error_message = "Every stack must declare at least one subnet. Remove the stack instead of leaving subnets empty. Offending stacks: ${join(", ", [for k, st in var.stack_subnets : k if length(st.subnets) == 0])}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for k, s in st.subnets : can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az))
      ]
    ]))
    error_message = "Subnet names may contain only lowercase letters, digits and '-'; az must be an AZ ID ending in -az<n>. Offending stack subnets: ${join(", ", flatten([for sk, st in var.stack_subnets : [for k, s in st.subnets : "${sk}/${k}" if !(can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az)))]]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [for s in st.subnets : can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":")]
    ]))
    error_message = "cidr must be a valid IPv4 CIDR such as 10.230.0.0/24. Offending stack subnets: ${join(", ", flatten([for sk, st in var.stack_subnets : [for k, s in st.subnets : "${sk}/${k}" if !(can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":"))]]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [for s in st.subnets : s.ipv6_index == null ? true : (s.ipv6_index >= 0 && s.ipv6_index <= 255)]
    ]))
    error_message = "ipv6_index must be between 0 and 255. Offending stack subnets: ${join(", ", flatten([for sk, st in var.stack_subnets : [for k, s in st.subnets : "${sk}/${k}" if s.ipv6_index == null ? false : !(s.ipv6_index >= 0 && s.ipv6_index <= 255)]]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : concat(
        [!contains(keys(st.tags), "Name")],
        [for s in st.subnets : !contains(keys(s.tags), "Name")]
      )
    ]))
    error_message = "tags must not contain the protected key \"Name\": the module sets it from the naming rule. Offending: ${join(", ", flatten([for sk, st in var.stack_subnets : concat(contains(keys(st.tags), "Name") ? ["${sk}.tags"] : [], [for k, s in st.subnets : "${sk}.subnets.${k}.tags" if contains(keys(s.tags), "Name")])]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for g, members in st.db_subnet_group :
        can(regex("^[a-z0-9-]+$", g)) &&
        alltrue([for m in members : contains(keys(st.subnets), m)]) &&
        # Only look up members that exist: Terraform does not short-circuit &&, so an unknown
        # member would fail this line with "Invalid index" before the message above is used
        # (ARCHITECTURE 9.2.2 last bullet, DEC-093 (2)).
        length(distinct([for m in members : st.subnets[m].az if contains(keys(st.subnets), m)])) >= 2
      ]
    ]))
    error_message = "db_subnet_group: group names must match ^[a-z0-9-]+$, members must be subnets of the same stack and span at least two AZs. Offending groups: ${join(", ", flatten([for sk, st in var.stack_subnets : [for g, members in st.db_subnet_group : "${sk}.db_subnet_group.${g}" if !(can(regex("^[a-z0-9-]+$", g)) && alltrue([for m in members : contains(keys(st.subnets), m)]) && length(distinct([for m in members : st.subnets[m].az if contains(keys(st.subnets), m)])) >= 2)]]))}. Members that are not subnets of that stack: ${join(", ", flatten([for sk, st in var.stack_subnets : [for g, members in st.db_subnet_group : [for m in members : "${sk}.db_subnet_group.${g}.${m}" if !contains(keys(st.subnets), m)]]]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for g, members in st.elasticache_subnet_group :
        can(regex("^[a-z0-9-]+$", g)) &&
        alltrue([for m in members : contains(keys(st.subnets), m)]) &&
        length(members) >= 1
      ]
    ]))
    error_message = "elasticache_subnet_group: group names must match ^[a-z0-9-]+$ and members must be non-empty subnets of the same stack. Offending groups: ${join(", ", flatten([for sk, st in var.stack_subnets : [for g, members in st.elasticache_subnet_group : "${sk}.elasticache_subnet_group.${g}" if !(can(regex("^[a-z0-9-]+$", g)) && alltrue([for m in members : contains(keys(st.subnets), m)]) && length(members) >= 1)]]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for g, members in st.redshift_subnet_group :
        can(regex("^[a-z0-9-]+$", g)) &&
        alltrue([for m in members : contains(keys(st.subnets), m)]) &&
        length(members) >= 1
      ]
    ]))
    error_message = "redshift_subnet_group: group names must match ^[a-z0-9-]+$ and members must be non-empty subnets of the same stack. Offending groups: ${join(", ", flatten([for sk, st in var.stack_subnets : [for g, members in st.redshift_subnet_group : "${sk}.redshift_subnet_group.${g}" if !(can(regex("^[a-z0-9-]+$", g)) && alltrue([for m in members : contains(keys(st.subnets), m)]) && length(members) >= 1)]]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for g, members in st.memorydb_subnet_group :
        can(regex("^[a-z0-9-]+$", g)) &&
        alltrue([for m in members : contains(keys(st.subnets), m)]) &&
        length(members) >= 1
      ]
    ]))
    error_message = "memorydb_subnet_group: group names must match ^[a-z0-9-]+$ and members must be non-empty subnets of the same stack. Offending groups: ${join(", ", flatten([for sk, st in var.stack_subnets : [for g, members in st.memorydb_subnet_group : "${sk}.memorydb_subnet_group.${g}" if !(can(regex("^[a-z0-9-]+$", g)) && alltrue([for m in members : contains(keys(st.subnets), m)]) && length(members) >= 1)]]))}."
  }
  validation {
    condition = alltrue([
      for field in ["db_subnet_group", "elasticache_subnet_group", "redshift_subnet_group", "memorydb_subnet_group"] :
      length(distinct(flatten([for st in var.stack_subnets : keys(st[field])]))) == length(flatten([for st in var.stack_subnets : keys(st[field])]))
    ])
    error_message = "Subnet group names must be unique across stacks within each group type (db, elasticache, redshift, memorydb); the group name alone is the resource key. Offending types: ${join(", ", [for field in ["db_subnet_group", "elasticache_subnet_group", "redshift_subnet_group", "memorydb_subnet_group"] : field if length(distinct(flatten([for st in var.stack_subnets : keys(st[field])]))) != length(flatten([for st in var.stack_subnets : keys(st[field])]))])}."
  }
  # The NACL rule checks are split so the message can name the rule that failed and the
  # reason it failed. All three implement V-21 and V-23 (ARCHITECTURE 9.2.1).
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for dir in ["ingress", "egress"] : [
          for name, r in st.nacl[dir] :
          can(regex("^[a-z0-9-]+$", name)) &&
          contains(["allow", "deny"], r.rule_action) &&
          r.rule_number >= 1 && r.rule_number <= 32766
        ]
      ] if st.nacl != null
    ]))
    error_message = "Stack NACL rule: names may contain only lowercase letters, digits and '-', rule_action must be allow|deny and rule_number must be 1-32766. Offending rules: ${join(", ", flatten([for sk, st in var.stack_subnets : [for dir in ["ingress", "egress"] : [for name, r in st.nacl[dir] : "${sk}/${dir}/${name}" if !(can(regex("^[a-z0-9-]+$", name)) && contains(["allow", "deny"], r.rule_action) && r.rule_number >= 1 && r.rule_number <= 32766)]] if st.nacl != null]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for dir in ["ingress", "egress"] : [
          for name, r in st.nacl[dir] :
          contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.protocol) &&
          (!contains(["tcp", "udp", "6", "17"], r.protocol) || (r.from_port != null && r.to_port != null)) &&
          (!contains(["icmp", "icmpv6", "1", "58"], r.protocol) || (r.icmp_type != null && r.icmp_code != null)) &&
          (r.protocol != "-1" || (r.from_port == null && r.to_port == null && r.icmp_type == null && r.icmp_code == null))
        ]
      ] if st.nacl != null
    ]))
    error_message = "Stack NACL rule: protocol must be -1|tcp|udp|icmp|icmpv6 or 6|17|1|58, tcp/udp need from_port and to_port, icmp/icmpv6 need icmp_type and icmp_code, and -1 takes no ports. Offending rules: ${join(", ", flatten([for sk, st in var.stack_subnets : [for dir in ["ingress", "egress"] : [for name, r in st.nacl[dir] : "${sk}/${dir}/${name}" if !(contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.protocol) && (!contains(["tcp", "udp", "6", "17"], r.protocol) || (r.from_port != null && r.to_port != null)) && (!contains(["icmp", "icmpv6", "1", "58"], r.protocol) || (r.icmp_type != null && r.icmp_code != null)) && (r.protocol != "-1" || (r.from_port == null && r.to_port == null && r.icmp_type == null && r.icmp_code == null)))]] if st.nacl != null]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for dir in ["ingress", "egress"] : [
          for name, r in st.nacl[dir] :
          ((r.cidr_block != null) != (r.ipv6_cidr_block != null)) &&
          (r.ipv6_cidr_block == null ? true : (r.ipv6_cidr_block == "vpc" ? true : (strcontains(r.ipv6_cidr_block, ":") && can(cidrhost(r.ipv6_cidr_block, 0)))))
        ]
      ] if st.nacl != null
    ]))
    error_message = "Stack NACL rule: set exactly one of cidr_block and ipv6_cidr_block, and ipv6_cidr_block must be an IPv6 CIDR or the reserved value \"vpc\". Offending rules: ${join(", ", flatten([for sk, st in var.stack_subnets : [for dir in ["ingress", "egress"] : [for name, r in st.nacl[dir] : "${sk}/${dir}/${name}" if !(((r.cidr_block != null) != (r.ipv6_cidr_block != null)) && (r.ipv6_cidr_block == null ? true : (r.ipv6_cidr_block == "vpc" ? true : (strcontains(r.ipv6_cidr_block, ":") && can(cidrhost(r.ipv6_cidr_block, 0))))))]] if st.nacl != null]))}."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for dir in ["ingress", "egress"] :
        length(distinct([for r in st.nacl[dir] : r.rule_number])) == length(st.nacl[dir])
      ] if st.nacl != null
    ]))
    error_message = "Stack NACL rule_number must be unique within a direction. Offending: ${join(", ", flatten([for sk, st in var.stack_subnets : [for dir in ["ingress", "egress"] : "${sk}/${dir}" if length(distinct([for r in st.nacl[dir] : r.rule_number])) != length(st.nacl[dir])] if st.nacl != null]))}."
  }
}

################################################################################
# Route Tables, NAT, ENI, Security Groups
################################################################################

variable "route_tables" {
  type = map(object({
    routes = optional(map(object({
      gateway              = optional(string)
      nat_gateway          = optional(string)
      eni                  = optional(string)
      network_interface_id = optional(string)
    })), {})
    propagate_vgw = optional(bool, false)
    tags          = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOF
Route tables keyed by caller-chosen name. Every subnet points to one of these keys. routes is
a destination -> target table: the key is a destination CIDR (IPv4 or IPv6) and the value
names exactly one target: gateway ("igw", "eigw" or "vgw" created by this module),
nat_gateway (a nat_gateways key), eni (an eni_interfaces key) or network_interface_id (an
ENI created by the caller). A route table with no routes has only the local route. The
Internet Gateway exists while at least one route targets "igw"; the Egress-only IGW while at
least one targets "eigw". Gateway VPC Endpoints attach to every route table automatically.
propagate_vgw enables VGW route propagation for that table. Changing a key recreates the
route table and its associations.

  route_tables = {
    pub    = { routes = { "0.0.0.0/0" = { gateway = "igw" } } }
    pri-a1 = { routes = { "0.0.0.0/0" = { nat_gateway = "a1" } } }
    iso    = {}
  }
EOF

  validation {
    condition     = alltrue([for k, rt in var.route_tables : can(regex("^[a-z0-9-]+$", k)) && !contains(keys(rt.tags), "Name")])
    error_message = "Route table keys may contain only lowercase letters, digits and '-'; tags must not contain the protected key \"Name\". Offending route tables: ${join(", ", [for k, rt in var.route_tables : k if !(can(regex("^[a-z0-9-]+$", k)) && !contains(keys(rt.tags), "Name"))])}."
  }
  validation {
    condition = alltrue(flatten([
      for rt in var.route_tables : [
        for dest, r in rt.routes :
        length([for v in [r.gateway, r.nat_gateway, r.eni, r.network_interface_id] : v if v != null]) == 1 &&
        (r.gateway == null ? true : contains(["igw", "eigw", "vgw"], r.gateway)) &&
        (r.network_interface_id == null ? true : startswith(r.network_interface_id, "eni-")) &&
        (r.gateway == "eigw" ? strcontains(dest, ":") : true)
      ]
    ]))
    error_message = "Each route must name exactly one target; gateway must be igw|eigw|vgw, network_interface_id must start with eni-, and eigw is only valid for an IPv6 destination. Offending routes: ${join(", ", flatten([for k, rt in var.route_tables : [for dest, r in rt.routes : "${k}/${dest}" if !(length([for v in [r.gateway, r.nat_gateway, r.eni, r.network_interface_id] : v if v != null]) == 1 && (r.gateway == null ? true : contains(["igw", "eigw", "vgw"], r.gateway)) && (r.network_interface_id == null ? true : startswith(r.network_interface_id, "eni-")) && (r.gateway == "eigw" ? strcontains(dest, ":") : true))]]))}."
  }
  # V-29. The destination key is the route key and decides whether the route is written to
  # destination_cidr_block or destination_ipv6_cidr_block. A malformed value passes every
  # other check and is only rejected by AWS at apply.
  validation {
    condition = alltrue(flatten([
      for rt in var.route_tables : [for dest, r in rt.routes : can(cidrhost(dest, 0))]
    ]))
    error_message = "Route destinations must be a valid IPv4 or IPv6 CIDR such as 0.0.0.0/0, 10.99.0.0/16 or ::/0. Offending routes: ${join(", ", flatten([for k, rt in var.route_tables : [for dest, r in rt.routes : "${k}/${dest}" if !can(cidrhost(dest, 0))]]))}."
  }
}

variable "nat_gateways" {
  type = map(object({
    public_subnet     = string
    eip_allocation_id = optional(string)
    tags              = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOF
NAT Gateways keyed by caller-chosen name. public_subnet is the name of a shared_public
subnet where the NAT is placed. When eip_allocation_id is omitted the module creates an EIP
with the same key; otherwise the given allocation is attached. Any number of route tables
may target one NAT, so adding a route table never adds a NAT. A route whose subnet is in a
different AZ than the NAT is a cross-AZ path: it works but incurs data-transfer cost and
shares that AZ's failure. Changing a key or public_subnet recreates the NAT.

  nat_gateways = {
    a1 = { public_subnet = "pub-a1" }
    c1 = { public_subnet = "pub-c1", eip_allocation_id = "eipalloc-0123456789abcdef0" }
  }
EOF

  validation {
    condition     = alltrue([for k, n in var.nat_gateways : can(regex("^[a-z0-9-]+$", k)) && !contains(keys(n.tags), "Name")])
    error_message = "NAT keys may contain only lowercase letters, digits and '-'; tags must not contain the protected key \"Name\". Offending NAT gateways: ${join(", ", [for k, n in var.nat_gateways : k if !(can(regex("^[a-z0-9-]+$", k)) && !contains(keys(n.tags), "Name"))])}."
  }
  # V-30. An allocation id that is not an allocation id (an EIP address, a public IP) passes
  # plan and is only rejected by AWS at apply.
  validation {
    condition     = alltrue([for n in var.nat_gateways : n.eip_allocation_id == null ? true : startswith(n.eip_allocation_id, "eipalloc-")])
    error_message = "nat_gateways.<key>.eip_allocation_id must be an Elastic IP allocation id starting with \"eipalloc-\", not the IP address itself. Offending NAT gateways: ${join(", ", [for k, n in var.nat_gateways : k if n.eip_allocation_id == null ? false : !startswith(n.eip_allocation_id, "eipalloc-")])}."
  }
}

variable "eni_interfaces" {
  type = map(object({
    subnet = string
    # private_ips keeps a null default on purpose: null means "let AWS pick an address"
    # and an empty set does not (RSC-ENI-03). The two security group sets do mean the
    # same thing when empty or null, so they default to [] (DEC-104).
    private_ips          = optional(set(string))
    security_group_names = optional(set(string), [])
    security_group_ids   = optional(set(string), [])
    source_dest_check    = optional(bool, true)
    interface_type       = optional(string)
    description          = optional(string)
    tags                 = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOF
Network interfaces created by this module in one of its subnets, keyed by caller-chosen
name. Routes target them with the eni field, so a NAT instance or appliance can be replaced
while the ENI, its private IP and the routes stay. subnet is any subnet name of this module.
Security groups are the union of security_group_names (keys of security_groups) and
security_group_ids (caller-created SGs); when both are empty AWS attaches the default SG,
which this module leaves with no rules, so the ENI cannot communicate. source_dest_check
defaults to true; a NAT or firewall appliance ENI must set it to false or forwarded traffic
is dropped. interface_type is ENA when null; "efa" and "efa-only" are accepted (efa-only
carries no IP traffic and cannot be a route target). Attaching the ENI to an instance is
the caller's job (aws_network_interface_attachment) and routes to an unattached ENI carry
no traffic, which plan cannot show. private_ips outside the subnet are rejected by AWS at
apply. Changing the map key, subnet or private_ips recreates the ENI.

  eni_interfaces = {
    natsvc-a1 = {
      subnet               = "pub-a1"
      private_ips          = ["10.230.0.13"]
      security_group_names = ["nat-appliance"]
      source_dest_check    = false
    }
  }
EOF

  validation {
    condition = alltrue([
      for k, e in var.eni_interfaces :
      can(regex("^[a-z0-9-]+$", k)) &&
      (e.interface_type == null ? true : contains(["efa", "efa-only"], e.interface_type)) &&
      !contains(keys(e.tags), "Name")
    ])
    error_message = "ENI keys may contain only lowercase letters, digits and '-'; interface_type must be null, efa or efa-only; tags must not contain the protected key \"Name\". Offending ENIs: ${join(", ", [for k, e in var.eni_interfaces : k if !(can(regex("^[a-z0-9-]+$", k)) && (e.interface_type == null ? true : contains(["efa", "efa-only"], e.interface_type)) && !contains(keys(e.tags), "Name"))])}."
  }
  # V-31. security_group_names takes module keys and security_group_ids takes caller-created
  # ids; swapping the two is the common mistake and only AWS would catch it at apply.
  validation {
    condition = alltrue(flatten([
      for e in var.eni_interfaces : [for id in e.security_group_ids : startswith(id, "sg-")]
    ]))
    error_message = "eni_interfaces.<key>.security_group_ids takes security group ids starting with \"sg-\"; use security_group_names for security_groups keys of this module. Offending ENIs: ${join(", ", [for k, e in var.eni_interfaces : k if !alltrue([for id in e.security_group_ids : startswith(id, "sg-")])])}."
  }
}

variable "security_groups" {
  type = map(object({
    description = optional(string)
    ingress = optional(map(object({
      ip_protocol                    = string
      from_port                      = optional(number)
      to_port                        = optional(number)
      cidr_ipv4                      = optional(string)
      cidr_ipv6                      = optional(string)
      prefix_list_id                 = optional(string)
      referenced_security_group_name = optional(string)
      referenced_security_group_id   = optional(string)
      description                    = optional(string)
    })), {})
    egress = optional(map(object({
      ip_protocol                    = string
      from_port                      = optional(number)
      to_port                        = optional(number)
      cidr_ipv4                      = optional(string)
      cidr_ipv6                      = optional(string)
      prefix_list_id                 = optional(string)
      referenced_security_group_name = optional(string)
      referenced_security_group_id   = optional(string)
      description                    = optional(string)
    })), {})
    tags = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOF
Security groups for the ENIs and Interface Endpoints this module creates, keyed by
caller-chosen name (the key "vpce" is reserved). ingress and egress are rule maps keyed by
rule name; each rule becomes one aws_vpc_security_group_*_rule, so callers may add rules to
the same group from outside without disturbing this module's plan. ip_protocol is "-1",
"tcp", "udp", "icmp", "icmpv6" or the matching number; tcp/udp need from_port and to_port,
icmp/icmpv6 carry the ICMP type in from_port and code in to_port (-1 for all), "-1" takes no
ports. Exactly one source is set: cidr_ipv4, cidr_ipv6, prefix_list_id,
referenced_security_group_name (another key here) or referenced_security_group_id. A
direction with no rules blocks all traffic: the module removes AWS's default allow-all
egress, so outbound needs an explicit egress rule. Changing the map key or description
recreates the group; changing a rule name replaces that rule.

  security_groups = {
    nat-appliance = {
      description = "NAT appliance ENI"
      ingress = {
        vpc-https = { ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "10.230.0.0/16" }
      }
      egress = {
        all = { ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" }
      }
    }
  }
EOF

  validation {
    condition     = alltrue([for k, sg in var.security_groups : can(regex("^[a-z0-9-]+$", k)) && k != "vpce" && !contains(keys(sg.tags), "Name")])
    error_message = "Security group keys may contain only lowercase letters, digits and '-', must not be the reserved key \"vpce\", and tags must not contain the protected key \"Name\". Offending security groups: ${join(", ", [for k, sg in var.security_groups : k if !(can(regex("^[a-z0-9-]+$", k)) && k != "vpce" && !contains(keys(sg.tags), "Name"))])}."
  }
  # The rule checks are split so the message can name the rule that failed and the reason
  # it failed. Both implement V-10 and V-11; the first also carries V-35, the sg- format of
  # referenced_security_group_id (ARCHITECTURE 9.2.1).
  validation {
    condition = alltrue(flatten([
      for sg in var.security_groups : [
        for dir in ["ingress", "egress"] : [
          for name, r in sg[dir] :
          can(regex("^[a-z0-9-]+$", name)) &&
          length([for v in [r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_name, r.referenced_security_group_id] : v if v != null]) == 1 &&
          (r.referenced_security_group_name == null ? true : contains(keys(var.security_groups), r.referenced_security_group_name)) &&
          (r.referenced_security_group_id == null ? true : startswith(r.referenced_security_group_id, "sg-"))
        ]
      ]
    ]))
    error_message = "Security group rule: names may contain only lowercase letters, digits and '-', exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_name and referenced_security_group_id must be set, referenced_security_group_name must be a key of security_groups and referenced_security_group_id must start with \"sg-\". Offending rules: ${join(", ", flatten([for sk, sg in var.security_groups : [for dir in ["ingress", "egress"] : [for name, r in sg[dir] : "${sk}/${dir}/${name}" if !(can(regex("^[a-z0-9-]+$", name)) && length([for v in [r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_name, r.referenced_security_group_id] : v if v != null]) == 1 && (r.referenced_security_group_name == null ? true : contains(keys(var.security_groups), r.referenced_security_group_name)) && (r.referenced_security_group_id == null ? true : startswith(r.referenced_security_group_id, "sg-")))]]]))}."
  }
  validation {
    condition = alltrue(flatten([
      for sg in var.security_groups : [
        for dir in ["ingress", "egress"] : [
          for name, r in sg[dir] :
          contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.ip_protocol) &&
          (r.ip_protocol == "-1" ? (r.from_port == null && r.to_port == null) : (r.from_port != null && r.to_port != null))
        ]
      ]
    ]))
    error_message = "Security group rule: ip_protocol must be -1|tcp|udp|icmp|icmpv6 or 6|17|1|58, \"-1\" takes no ports, and every other protocol needs from_port and to_port (icmp carries the type in from_port and the code in to_port, -1 for all). Offending rules: ${join(", ", flatten([for sk, sg in var.security_groups : [for dir in ["ingress", "egress"] : [for name, r in sg[dir] : "${sk}/${dir}/${name}" if !(contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.ip_protocol) && (r.ip_protocol == "-1" ? (r.from_port == null && r.to_port == null) : (r.from_port != null && r.to_port != null)))]]]))}."
  }
}

################################################################################
# Shared services
################################################################################

variable "vpc_endpoints" {
  type = object({
    gateway = optional(set(string), [])
    interface = optional(map(object({
      private_dns_enabled  = optional(bool, true)
      policy               = optional(string)
      security_group_names = optional(set(string), [])
      security_group_ids   = optional(set(string), [])
    })), {})
  })
  # An empty object and null mean the same thing here (no endpoints at all), unlike
  # shared_public or flow-log style inputs where an empty object means "create one with
  # defaults". nullable = false makes an explicit null fall back to {} (DEC-104).
  default     = {}
  nullable    = false
  description = <<-EOF
VPC Endpoints. gateway lists Gateway Endpoint services ("s3", "dynamodb"); each is attached to
every route table. interface is keyed by service name (e.g. "ecr.api") and the service name
is built as com.amazonaws.<context.region>.<service>; the ENIs are placed in every
vpc_endpoint_subnets subnet, which must therefore be non-empty. Security groups are the union
of security_group_names (keys of security_groups) and security_group_ids; when both are empty
for at least one endpoint the module creates one endpoint security group allowing 443 from
the VPC CIDRs (and the VPC IPv6 CIDR when enable_ipv6 is true).

  vpc_endpoints = {
    gateway   = ["s3", "dynamodb"]
    interface = { "sts" = {}, "ssm" = {} }
  }
EOF

  validation {
    condition     = alltrue([for g in var.vpc_endpoints.gateway : contains(["s3", "dynamodb"], g)])
    error_message = "vpc_endpoints.gateway may contain only \"s3\" and \"dynamodb\"; every other service is an Interface Endpoint. Offending services: ${join(", ", [for g in var.vpc_endpoints.gateway : g if !contains(["s3", "dynamodb"], g)])}."
  }
  # V-32. Same mistake as eni_interfaces: module keys belong in security_group_names.
  validation {
    condition = alltrue(flatten([
      for e in var.vpc_endpoints.interface : [for id in e.security_group_ids : startswith(id, "sg-")]
    ]))
    error_message = "vpc_endpoints.interface.<service>.security_group_ids takes security group ids starting with \"sg-\"; use security_group_names for security_groups keys of this module. Offending services: ${join(", ", [for svc, e in var.vpc_endpoints.interface : svc if !alltrue([for id in e.security_group_ids : startswith(id, "sg-")])])}."
  }
}

variable "vpn_gateway" {
  type = object({
    amazon_side_asn   = optional(string)
    availability_zone = optional(string)
    existing_id       = optional(string)
  })
  default     = null
  description = <<-EOF
Virtual Private Gateway. When non-null a VGW is created (or, with existing_id, an existing
VGW is attached to this VPC). amazon_side_asn defaults to AWS's 64512 when null.
availability_zone is an AZ name (not an AZ ID). Route propagation is enabled per route table
with propagate_vgw; VPN connections are out of scope. existing_id cannot be combined with
amazon_side_asn or availability_zone.

  vpn_gateway = { amazon_side_asn = "64512" }
EOF

  validation {
    condition     = try(var.vpn_gateway.existing_id, null) == null ? true : (var.vpn_gateway.amazon_side_asn == null && var.vpn_gateway.availability_zone == null)
    error_message = "vpn_gateway.existing_id cannot be combined with amazon_side_asn or availability_zone: those two configure a VGW this module creates, existing_id attaches one it does not own."
  }
  # V-33
  validation {
    condition     = try(var.vpn_gateway.existing_id, null) == null ? true : startswith(var.vpn_gateway.existing_id, "vgw-")
    error_message = "vpn_gateway.existing_id must be a Virtual Private Gateway id starting with \"vgw-\"."
  }
}

variable "customer_gateways" {
  type = map(object({
    bgp_asn     = string
    ip_address  = string
    device_name = optional(string)
    tags        = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOF
Customer Gateways keyed by caller-chosen name (type is always ipsec.1). VPN connections are
out of scope; use the cgw_ids and vgw_id outputs to create them.

  customer_gateways = {
    hq-fw-1 = { bgp_asn = "65000", ip_address = "203.0.113.10", device_name = "hq-fw-1" }
  }
EOF

  validation {
    condition     = alltrue([for k, c in var.customer_gateways : can(regex("^[a-z0-9-]+$", k)) && !contains(keys(c.tags), "Name")])
    error_message = "Customer gateway keys may contain only lowercase letters, digits and '-'; tags must not contain the protected key \"Name\". Offending customer gateways: ${join(", ", [for k, c in var.customer_gateways : k if !(can(regex("^[a-z0-9-]+$", k)) && !contains(keys(c.tags), "Name"))])}."
  }
}

variable "flow_logs" {
  type = map(object({
    log_destination_arn      = string
    log_destination_type     = string
    iam_role_arn             = optional(string)
    traffic_type             = optional(string, "ALL")
    max_aggregation_interval = optional(number, 600)
    log_format               = optional(string, "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}")
    destination_options = optional(object({
      file_format                = optional(string, "parquet")
      hive_compatible_partitions = optional(bool, true)
      per_hour_partition         = optional(bool, true)
    }))
  }))
  default     = {}
  description = <<-EOF
VPC Flow Logs, one aws_flow_log per entry. A flow log carries one destination, so sending
the same VPC to several places means one entry per place; leaving an entry out removes only
that flow log and an empty map creates none. The map key is a caller-chosen name and becomes
the resource key and the Name tag segment. This module never creates the destination itself:
the log group, bucket, delivery stream, IAM roles, bucket policy and KMS key policy belong to
the stack that owns them and are referenced here by ARN.

log_destination_type is "cloud-watch-logs", "s3" or "kinesis-data-firehose" and
log_destination_arn is that destination's ARN (a log group ARN, conventionally with the ":*"
suffix; a bucket ARN, optionally with a key prefix; or a delivery stream ARN). An s3 bucket
policy must allow delivery.logs.amazonaws.com, and a cross-account bucket needs a customer
managed KMS key whose policy allows the delivering account or organization; both are out of
scope. iam_role_arn is required for cloud-watch-logs and rejected for s3, and plan fails on either
mistake. kinesis-data-firehose is not checked: same-account delivery needs a role and
cross-account delivery must omit it, and nothing in this input tells the two apart, so AWS
decides that one at apply.

destination_options applies to the s3 destination only and is rejected on the others. Its
defaults are parquet with Hive-compatible and hourly partitions. log_format defaults to the
29 AWS v2-v5 fields in AWS order, which the central Athena table columns match one to one;
override it only together with that table.

  flow_logs = {
    s3 = {
      log_destination_type = "s3"
      log_destination_arn  = "arn:aws:s3:::org-vpc-flowlogs/platform"
    }
    cloudwatch = {
      log_destination_type = "cloud-watch-logs"
      log_destination_arn  = "arn:aws:logs:ap-northeast-2:111122223333:log-group:/vpc/flowlogs:*"
      iam_role_arn         = "arn:aws:iam::111122223333:role/flowlogs-to-cloudwatch"
    }
  }
EOF

  validation {
    condition = alltrue([
      for k, d in var.flow_logs :
      can(regex("^[a-z0-9-]+$", k)) &&
      contains(["cloud-watch-logs", "s3", "kinesis-data-firehose"], d.log_destination_type) &&
      contains(["ACCEPT", "REJECT", "ALL"], d.traffic_type) &&
      contains([60, 600], d.max_aggregation_interval)
    ])
    error_message = "flow_logs: keys may contain only lowercase letters, digits and '-'; log_destination_type must be cloud-watch-logs|s3|kinesis-data-firehose, traffic_type ACCEPT|REJECT|ALL, max_aggregation_interval 60|600. Offending entries: ${join(", ", [for k, d in var.flow_logs : k if !(can(regex("^[a-z0-9-]+$", k)) && contains(["cloud-watch-logs", "s3", "kinesis-data-firehose"], d.log_destination_type) && contains(["ACCEPT", "REJECT", "ALL"], d.traffic_type) && contains([60, 600], d.max_aggregation_interval))])}."
  }
  validation {
    condition = alltrue([
      for d in var.flow_logs :
      d.destination_options == null ? true : (
        d.log_destination_type == "s3" &&
        contains(["parquet", "plain-text"], d.destination_options.file_format)
      )
    ])
    error_message = "flow_logs: destination_options is valid only for the s3 destination type, and file_format must be parquet|plain-text. Offending entries: ${join(", ", [for k, d in var.flow_logs : k if d.destination_options == null ? false : !(d.log_destination_type == "s3" && contains(["parquet", "plain-text"], d.destination_options.file_format))])}."
  }
  # kinesis-data-firehose is left out: same-account delivery needs a role and cross-account
  # delivery must omit it, and the input carries nothing that tells the two apart.
  validation {
    condition = alltrue([
      for d in var.flow_logs :
      d.log_destination_type == "cloud-watch-logs" ? d.iam_role_arn != null : (
        d.log_destination_type == "s3" ? d.iam_role_arn == null : true
      )
    ])
    error_message = "flow_logs: the cloud-watch-logs destination requires iam_role_arn and the s3 destination must not set it. Offending entries: ${join(", ", [for k, d in var.flow_logs : k if !(d.log_destination_type == "cloud-watch-logs" ? d.iam_role_arn != null : (d.log_destination_type == "s3" ? d.iam_role_arn == null : true))])}."
  }
}

variable "private_dns" {
  type = object({
    domain_name        = optional(string)
    additional_vpc_ids = optional(set(string), [])
  })
  default     = null
  description = <<-EOF
Route53 Private Hosted Zone associated with this VPC. domain_name defaults to
context.pri_domain; when both are null plan fails. additional_vpc_ids associates other VPCs
of the same account.

  private_dns = {}
EOF

  # V-34
  validation {
    condition     = try(var.private_dns.additional_vpc_ids, null) == null ? true : alltrue([for id in var.private_dns.additional_vpc_ids : startswith(id, "vpc-")])
    error_message = "private_dns.additional_vpc_ids takes VPC ids starting with \"vpc-\". Offending values: ${join(", ", try(var.private_dns.additional_vpc_ids, null) == null ? [] : [for id in var.private_dns.additional_vpc_ids : id if !startswith(id, "vpc-")])}."
  }
}

variable "dhcp_options" {
  type = object({
    domain_name          = optional(string)
    domain_name_servers  = optional(list(string), ["AmazonProvidedDNS"])
    ntp_servers          = optional(list(string), [])
    netbios_name_servers = optional(list(string), [])
    netbios_node_type    = optional(string)
  })
  default     = null
  description = <<-EOF
DHCP Options set created and associated when non-null. domain_name defaults to
context.pri_domain; when both are null plan fails. netbios_node_type is "1", "2", "4" or "8".

  dhcp_options = {}
EOF

  validation {
    condition     = try(var.dhcp_options.netbios_node_type, null) == null ? true : contains(["1", "2", "4", "8"], var.dhcp_options.netbios_node_type)
    error_message = "dhcp_options.netbios_node_type must be \"1\", \"2\", \"4\" or \"8\"."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Custom tags applied to every resource this module creates, merged after context.tags and before per-resource tags. Must not contain the protected key \"Name\"."

  validation {
    condition     = !contains(keys(var.tags), "Name")
    error_message = "tags must not contain the protected key \"Name\"."
  }
}
