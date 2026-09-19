################################################################################
# VPC Flow Logs (REQUIREMENTS 6.12). One aws_flow_log per destination: the AWS
# resource carries a single destination, so the same VPC reaches several places
# only by declaring one entry per place. Destination resources (log group,
# bucket, delivery stream, IAM roles) belong to the stack that owns them and are
# referenced here by ARN (RSC-FLOW-08).
################################################################################

resource "aws_flow_log" "this" {
  for_each = var.flow_log == null ? {} : var.flow_log.destinations

  vpc_id                   = aws_vpc.this.id
  log_destination          = each.value.log_destination_arn
  log_destination_type     = each.value.log_destination_type
  iam_role_arn             = each.value.iam_role_arn
  traffic_type             = each.value.traffic_type
  max_aggregation_interval = each.value.max_aggregation_interval
  log_format               = each.value.log_format

  # Rendered only where the caller set it, which validation limits to s3 (RSC-FLOW-05).
  dynamic "destination_options" {
    for_each = each.value.destination_options == null ? [] : [each.value.destination_options]

    content {
      file_format                = destination_options.value.file_format
      hive_compatible_partitions = destination_options.value.hive_compatible_partitions
      per_hour_partition         = destination_options.value.per_hour_partition
    }
  }

  tags = merge(local.tags_base, { Name = "${local.prefix}-${each.key}-vpc-flow" })
}
