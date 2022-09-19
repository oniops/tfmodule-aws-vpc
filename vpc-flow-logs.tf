locals {
  enable_flow_log = var.create_vpc && var.enable_flow_log
}

################################################################################
# Flow Log
################################################################################

resource "aws_flow_log" "this" {
  count = local.enable_flow_log ? 1 : 0

  vpc_id                   = local.vpc_id
  log_destination_type     = var.flow_log_destination_type
  log_destination          = var.flow_log_destination_arn
  log_format               = var.flow_log_format
  #
  # iam_role_arn             = var.flow_log_cloudwatch_iam_role_arn
  traffic_type             = var.flow_log_traffic_type
  max_aggregation_interval = var.flow_log_max_aggregation_interval

  destination_options {
    file_format                = var.flow_log_file_format
    hive_compatible_partitions = var.flow_log_hive_compatible_partitions
    per_hour_partition         = var.flow_log_per_hour_partition
  }

  tags = merge(var.tags, var.vpc_flow_log_tags)
}
