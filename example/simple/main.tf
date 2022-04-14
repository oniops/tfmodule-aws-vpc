module "ctx" {
  source = "git::https://code.bespinglobal.com/scm/op/tfmodule-context.git"
  context = var.context
}

module "vpc" {
  source = "../../"

  context = module.ctx.context
  cidr    = "171.2.0.0/16"

  azs = [ data.aws_availability_zones.this.zone_ids[0], data.aws_availability_zones.this.zone_ids[1] ]

  public_subnet_names  = ["pub-a1", "pub-b1"]
  public_subnets       = ["171.2.11.0/24", "171.2.12.0/24"]
  public_subnet_suffix = "pub"

  enable_nat_gateway = true
  single_nat_gateway = true

  private_subnet_names = ["pri-a1", "pri-b1"]
  private_subnets      = ["171.2.31.0/24", "171.2.32.0/24"]

  depends_on = [module.ctx]
}


data "aws_availability_zones" "this" {
  state = "available"
}
