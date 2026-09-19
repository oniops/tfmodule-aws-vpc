variable "context" {
  type = object({
    project     = string
    environment = optional(string)
    name_prefix = string
    region      = string
    pri_domain  = string
    tags        = map(string)
    owner       = optional(string)
    team        = optional(string)
    cost_center = optional(string)
  })
  description = <<-EOF
Output object of the tfmodule-context module (reference version v1.3.5). This module uses
name_prefix (resource name prefix), tags (first stage of tag merging), region (Interface
VPC Endpoint service names) and pri_domain (default domain for Private DNS and DHCP options).
The remaining fields are accepted for compatibility and not used.

Required fields may still carry a null value: pri_domain is needed only when domain_name is
omitted for dhcp_options or private_dns, and region only when an Interface VPC Endpoint is
declared. In both cases a null value fails at plan time.

name_prefix is prefixed to every resource name. For resources whose name is an argument
rather than a tag (subnet groups, endpoint SG, flow-log log group and IAM role, hosted zone)
the combined name must stay inside the AWS limit; the shortest is 64 characters for the IAM
role. The module does not check the final length, so keep name_prefix short.

  module "ctx" {
    source  = "git::https://github.com/oniops/tfmodule-context.git?ref=v1.3.5"
    context = var.context
  }

  module "vpc" {
    source  = "git::https://github.com/oniops/tfmodule-aws-vpc.git?ref=<tag>"
    context = module.ctx.context
  }
EOF

}
