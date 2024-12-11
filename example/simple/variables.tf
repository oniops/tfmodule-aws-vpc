variable "context" {
  type = object({
    aws_profile             = string # describe a specifc profile to access a aws cli
    region                  = string # describe default region to create a resource from aws
    project                 = string # project name is usally account's project name or platform name
    environment             = string # Runtime Environment such as develop, stage, production
    owner                   = string # project owner
    team                    = string # Team name of Devops Transformation
    cost_center             = number # Cost Center
    domain                  = string # Team name of Devops Transformation
    pri_domain              = string # Team name of Devops Transformation
    customer   = string
    department   = string
  })
  default = {
    aws_profile             = null
    region                  = null
    project                 = null
    environment             = "Development"
    owner                   = null
    team                    = null
    cost_center             = null
    domain                  = null
    pri_domain              = null
    customer              = null
    department              = null
  }
}