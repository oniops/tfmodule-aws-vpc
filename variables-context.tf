variable "context" {
  type = object({
    project      = string
    name_prefix  = string
    region       = string
    pri_domain   = string
    tags         = map(string)
    environment  = optional(string)
    owner        = optional(string)
    team         = optional(string)
    cost_center  = optional(number)
  })
  description = <<-EOF
Output object of the tfmodule-context module (reference version v1.3.5 or later). This module
uses name_prefix (resource name prefix), tags (first stage of tag merging), region (Interface
VPC Endpoint service names) and pri_domain (default domain for Private DNS and DHCP options).
The remaining fields are accepted for compatibility and not used; fields of the reference
output that are not listed here are dropped by the object type without an error.

Required fields may still carry a null value: pri_domain is needed only when domain_name is
omitted for dhcp_options or private_dns, and region only when an Interface VPC Endpoint is
declared. In both cases a null value fails at plan time. name_prefix and tags are used by
every resource, so a null value there fails the whole plan.

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

  # V-28. Without this the first resource that builds a name or merges tags fails with a
  # Terraform internal error (null in string interpolation, merge() on null) instead of
  # naming the field the caller has to fix.
  validation {
    condition     = var.context.name_prefix != null && var.context.tags != null
    error_message = "context.name_prefix and context.tags must not be null: every resource name and tag set is derived from them. Check that module \"ctx\" is a tfmodule-context v1.3.5 or later release."
  }
}
