data "aws_availability_zones" "this" {
  state = "available"
}

module "ctx" {
  source = "git::https://code.bespinglobal.com/scm/op/tfmodule-context.git"
  context = var.context
}

resource "aws_s3_bucket" "flow" {
  bucket = "${module.ctx.project}-vpc-flow-s3"

  tags = merge(module.ctx.tags,
    { Name = "${module.ctx.project}-vpc-flow-s3" }
  )
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

  enable_flow_log = true
  flow_log_destination_type = "s3"
  flow_log_destination_arn  = aws_s3_bucket.flow.arn
  flow_log_file_format      = "parquet"

  depends_on = [module.ctx]
}

resource "aws_s3_bucket_acl" "flow" {
  bucket = aws_s3_bucket.flow.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "flow" {
  bucket = aws_s3_bucket.flow.id
  rule {
    id = "purge"
    expiration {
      days = 365
    }
    filter {
      prefix = "AWSLogs/"
    }
    status = "Enabled"
  }
  depends_on = [aws_s3_bucket.flow]
}
