################################################################################
# VPC
################################################################################

variable "vpc_cidr" {
  type        = string
  description = "Primary IPv4 CIDR of the VPC. Changing it recreates the VPC."

  # Checked here so a malformed value fails with this message instead of an internal
  # error from the CIDR arithmetic in locals.tf (POLICIES 6.1).
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
    error_message = "secondary_cidrs entries must be valid IPv4 CIDRs such as 100.64.0.0/16."
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
  type = object({
    tags = optional(map(string), {})
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
    subnets = map(object({
      az          = string
      cidr        = string
      route_table = string
      ipv6_index  = optional(number)
      tags        = optional(map(string), {})
    }))
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
    error_message = "shared_public.subnets must contain at least one subnet."
  }
  validation {
    condition = var.shared_public == null ? true : alltrue([
      for k, s in var.shared_public.subnets : can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az))
    ])
    error_message = "Subnet names may contain only lowercase letters, digits and '-'; az must be an AZ ID ending in -az<n>."
  }
  validation {
    condition = var.shared_public == null ? true : alltrue([
      for s in var.shared_public.subnets : can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":")
    ])
    error_message = "cidr must be a valid IPv4 CIDR such as 10.230.0.0/24."
  }
  validation {
    condition = var.shared_public == null ? true : alltrue([
      for s in var.shared_public.subnets : s.ipv6_index == null ? true : (s.ipv6_index >= 0 && s.ipv6_index <= 255)
    ])
    error_message = "ipv6_index must be between 0 and 255."
  }
  validation {
    condition = var.shared_public == null ? true : (
      !contains(keys(var.shared_public.tags), "Name") &&
      alltrue([for s in var.shared_public.subnets : !contains(keys(s.tags), "Name")])
    )
    error_message = "tags must not contain the protected key \"Name\"."
  }
  validation {
    condition = try(var.shared_public.nacl, null) == null ? true : alltrue(flatten([
      for dir in ["ingress", "egress"] : [
        for name, r in var.shared_public.nacl[dir] :
        can(regex("^[a-z0-9-]+$", name)) &&
        contains(["allow", "deny"], r.rule_action) &&
        contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.protocol) &&
        r.rule_number >= 1 && r.rule_number <= 32766 &&
        ((r.cidr_block != null) != (r.ipv6_cidr_block != null)) &&
        (r.ipv6_cidr_block == null ? true : (r.ipv6_cidr_block == "vpc" ? true : (strcontains(r.ipv6_cidr_block, ":") && can(cidrhost(r.ipv6_cidr_block, 0))))) &&
        (!contains(["tcp", "udp", "6", "17"], r.protocol) || (r.from_port != null && r.to_port != null)) &&
        (!contains(["icmp", "icmpv6", "1", "58"], r.protocol) || (r.icmp_type != null && r.icmp_code != null)) &&
        (r.protocol != "-1" || (r.from_port == null && r.to_port == null && r.icmp_type == null && r.icmp_code == null))
      ]
    ]))
    error_message = "Shared Public NACL rule is invalid: check rule name charset, rule_action (allow|deny), protocol (-1|tcp|udp|icmp|icmpv6 or 6|17|1|58), rule_number (1-32766), exactly one of cidr_block/ipv6_cidr_block, ports for tcp/udp, icmp_type/icmp_code for icmp, and no ports for -1."
  }
  validation {
    condition = try(var.shared_public.nacl, null) == null ? true : alltrue([
      for dir in ["ingress", "egress"] :
      length(distinct([for r in var.shared_public.nacl[dir] : r.rule_number])) == length(var.shared_public.nacl[dir])
    ])
    error_message = "Shared Public NACL rule_number must be unique within a direction."
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
    error_message = "Subnet names may contain only lowercase letters, digits and '-'; az must be an AZ ID ending in -az<n>."
  }
  validation {
    condition     = alltrue([for s in var.vpc_endpoint_subnets : can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":")])
    error_message = "cidr must be a valid IPv4 CIDR such as 10.230.0.0/24."
  }
  validation {
    condition     = alltrue([for s in var.vpc_endpoint_subnets : s.ipv6_index == null ? true : (s.ipv6_index >= 0 && s.ipv6_index <= 255)])
    error_message = "ipv6_index must be between 0 and 255."
  }
  validation {
    condition     = length(distinct([for s in var.vpc_endpoint_subnets : s.az])) == length(var.vpc_endpoint_subnets)
    error_message = "vpc_endpoint_subnets may contain at most one subnet per AZ."
  }
  validation {
    condition     = alltrue([for s in var.vpc_endpoint_subnets : !contains(keys(s.tags), "Name")])
    error_message = "tags must not contain the protected key \"Name\"."
  }
}

################################################################################
# Workload stacks
################################################################################

variable "stack_subnets" {
  type = map(object({
    tags = optional(map(string), {})
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
    subnets = map(object({
      az          = string
      cidr        = string
      route_table = string
      ipv6_index  = optional(number)
      tags        = optional(map(string), {})
    }))
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
    error_message = "Stack keys may contain only lowercase letters, digits and '-' and must not start with \"shared-\"."
  }
  validation {
    condition     = alltrue([for st in var.stack_subnets : length(st.subnets) > 0])
    error_message = "Every stack must declare at least one subnet."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for k, s in st.subnets : can(regex("^[a-z0-9-]+$", k)) && can(regex("-az[0-9]+$", s.az))
      ]
    ]))
    error_message = "Subnet names may contain only lowercase letters, digits and '-'; az must be an AZ ID ending in -az<n>."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [for s in st.subnets : can(cidrhost(s.cidr, 0)) && !strcontains(s.cidr, ":")]
    ]))
    error_message = "cidr must be a valid IPv4 CIDR such as 10.230.0.0/24."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [for s in st.subnets : s.ipv6_index == null ? true : (s.ipv6_index >= 0 && s.ipv6_index <= 255)]
    ]))
    error_message = "ipv6_index must be between 0 and 255."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : concat(
        [!contains(keys(st.tags), "Name")],
        [for s in st.subnets : !contains(keys(s.tags), "Name")]
      )
    ]))
    error_message = "tags must not contain the protected key \"Name\"."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for g, members in st.db_subnet_group :
        can(regex("^[a-z0-9-]+$", g)) &&
        alltrue([for m in members : contains(keys(st.subnets), m)]) &&
        length(distinct([for m in members : st.subnets[m].az])) >= 2
      ]
    ]))
    error_message = "db_subnet_group: group names must match ^[a-z0-9-]+$, members must be subnets of the same stack and span at least two AZs."
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
    error_message = "elasticache_subnet_group: group names must match ^[a-z0-9-]+$ and members must be non-empty subnets of the same stack."
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
    error_message = "redshift_subnet_group: group names must match ^[a-z0-9-]+$ and members must be non-empty subnets of the same stack."
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
    error_message = "memorydb_subnet_group: group names must match ^[a-z0-9-]+$ and members must be non-empty subnets of the same stack."
  }
  validation {
    condition = alltrue([
      for field in ["db_subnet_group", "elasticache_subnet_group", "redshift_subnet_group", "memorydb_subnet_group"] :
      length(distinct(flatten([for st in var.stack_subnets : keys(st[field])]))) == length(flatten([for st in var.stack_subnets : keys(st[field])]))
    ])
    error_message = "Subnet group names must be unique across stacks within each group type (db, elasticache, redshift, memorydb)."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for dir in ["ingress", "egress"] : [
          for name, r in st.nacl[dir] :
          can(regex("^[a-z0-9-]+$", name)) &&
          contains(["allow", "deny"], r.rule_action) &&
          contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.protocol) &&
          r.rule_number >= 1 && r.rule_number <= 32766 &&
          ((r.cidr_block != null) != (r.ipv6_cidr_block != null)) &&
          (r.ipv6_cidr_block == null ? true : (r.ipv6_cidr_block == "vpc" ? true : (strcontains(r.ipv6_cidr_block, ":") && can(cidrhost(r.ipv6_cidr_block, 0))))) &&
          (!contains(["tcp", "udp", "6", "17"], r.protocol) || (r.from_port != null && r.to_port != null)) &&
          (!contains(["icmp", "icmpv6", "1", "58"], r.protocol) || (r.icmp_type != null && r.icmp_code != null)) &&
          (r.protocol != "-1" || (r.from_port == null && r.to_port == null && r.icmp_type == null && r.icmp_code == null))
        ]
      ] if st.nacl != null
    ]))
    error_message = "Stack NACL rule is invalid: check rule name charset, rule_action (allow|deny), protocol (-1|tcp|udp|icmp|icmpv6 or 6|17|1|58), rule_number (1-32766), exactly one of cidr_block/ipv6_cidr_block, ports for tcp/udp, icmp_type/icmp_code for icmp, and no ports for -1."
  }
  validation {
    condition = alltrue(flatten([
      for st in var.stack_subnets : [
        for dir in ["ingress", "egress"] :
        length(distinct([for r in st.nacl[dir] : r.rule_number])) == length(st.nacl[dir])
      ] if st.nacl != null
    ]))
    error_message = "Stack NACL rule_number must be unique within a direction."
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
    error_message = "Route table keys may contain only lowercase letters, digits and '-'; tags must not contain \"Name\"."
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
    error_message = "Each route must name exactly one target; gateway must be igw|eigw|vgw, network_interface_id must start with eni-, and eigw is only valid for an IPv6 destination."
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
    error_message = "NAT keys may contain only lowercase letters, digits and '-'; tags must not contain \"Name\"."
  }
}

variable "eni_interfaces" {
  type = map(object({
    subnet               = string
    private_ips          = optional(set(string))
    security_group_names = optional(set(string))
    security_group_ids   = optional(set(string))
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
    error_message = "ENI keys may contain only lowercase letters, digits and '-'; interface_type must be null, efa or efa-only; tags must not contain \"Name\"."
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
    error_message = "Security group keys may contain only lowercase letters, digits and '-', must not be \"vpce\", and tags must not contain \"Name\"."
  }
  validation {
    condition = alltrue(flatten([
      for sg in var.security_groups : [
        for dir in ["ingress", "egress"] : [
          for name, r in sg[dir] :
          can(regex("^[a-z0-9-]+$", name)) &&
          contains(["-1", "tcp", "udp", "icmp", "icmpv6", "6", "17", "1", "58"], r.ip_protocol) &&
          length([for v in [r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_name, r.referenced_security_group_id] : v if v != null]) == 1 &&
          (r.ip_protocol == "-1" ? (r.from_port == null && r.to_port == null) : (r.from_port != null && r.to_port != null)) &&
          (r.referenced_security_group_name == null ? true : contains(keys(var.security_groups), r.referenced_security_group_name))
        ]
      ]
    ]))
    error_message = "Security group rule is invalid: check rule name charset, ip_protocol (-1|tcp|udp|icmp|icmpv6 or 6|17|1|58), exactly one source field, from_port/to_port required unless ip_protocol is -1, and referenced_security_group_name must be a key of security_groups."
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
      security_group_names = optional(set(string))
      security_group_ids   = optional(set(string))
    })), {})
  })
  default     = null
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
    condition     = var.vpc_endpoints == null ? true : alltrue([for g in var.vpc_endpoints.gateway : contains(["s3", "dynamodb"], g)])
    error_message = "vpc_endpoints.gateway may contain only \"s3\" and \"dynamodb\"."
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
    error_message = "vpn_gateway.existing_id cannot be combined with amazon_side_asn or availability_zone."
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
    error_message = "Customer gateway keys may contain only lowercase letters, digits and '-'; tags must not contain \"Name\"."
  }
}

variable "flow_log" {
  type = object({
    destinations = map(object({
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
  })
  default     = null
  description = <<-EOF
VPC Flow Logs, one aws_flow_log per entry of destinations. A flow log carries one
destination, so sending the same VPC to several places means one entry per place; leaving an
entry out removes only that flow log. The map key is a caller-chosen name and becomes the
resource key and the Name tag segment. This module never creates the destination itself: the
log group, bucket, delivery stream, IAM roles, bucket policy and KMS key policy belong to the
stack that owns them and are referenced here by ARN.

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

  flow_log = {
    destinations = {
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
  }
EOF

  validation {
    condition     = var.flow_log == null ? true : length(var.flow_log.destinations) > 0
    error_message = "flow_log.destinations must contain at least one destination; omit flow_log entirely to create none."
  }
  validation {
    condition = var.flow_log == null ? true : alltrue([
      for k, d in var.flow_log.destinations :
      can(regex("^[a-z0-9-]+$", k)) &&
      contains(["cloud-watch-logs", "s3", "kinesis-data-firehose"], d.log_destination_type) &&
      contains(["ACCEPT", "REJECT", "ALL"], d.traffic_type) &&
      contains([60, 600], d.max_aggregation_interval)
    ])
    error_message = "flow_log.destinations: keys may contain only lowercase letters, digits and '-'; log_destination_type must be cloud-watch-logs|s3|kinesis-data-firehose, traffic_type ACCEPT|REJECT|ALL, max_aggregation_interval 60|600."
  }
  validation {
    condition = var.flow_log == null ? true : alltrue([
      for d in var.flow_log.destinations :
      d.destination_options == null ? true : (
        d.log_destination_type == "s3" &&
        contains(["parquet", "plain-text"], d.destination_options.file_format)
      )
    ])
    error_message = "flow_log.destinations: destination_options is valid only for the s3 destination type, and file_format must be parquet|plain-text."
  }
  # kinesis-data-firehose is left out: same-account delivery needs a role and cross-account
  # delivery must omit it, and the input carries nothing that tells the two apart.
  validation {
    condition = var.flow_log == null ? true : alltrue([
      for d in var.flow_log.destinations :
      d.log_destination_type == "cloud-watch-logs" ? d.iam_role_arn != null : (
        d.log_destination_type == "s3" ? d.iam_role_arn == null : true
      )
    ])
    error_message = "flow_log.destinations: the cloud-watch-logs destination requires iam_role_arn and the s3 destination must not set it."
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
