# locals {
#   name_prefix = length(var.vpc_name) > 0 ? var.vpc_name : var.vpc_id
#   name        = "${local.name_prefix}-vpc-logs-to-splunk"
# }

# resource "aws_flow_log" "vpc" {
#   log_destination          = module.vpc_logs_to_splunk.log_destination
#   log_destination_type     = "kinesis-data-firehose"
#   traffic_type             = "ALL"
#   vpc_id                   = var.vpc_id
#   max_aggregation_interval = var.flow_log_max_aggregation_interval
#   log_format               = var.log_format
# }


resource "aws_route53_resolver_query_log_config" "vpc-route53-query-log-to-splunk" {
  name            = "vpc-route53-query-log-to-splunk"
  destination_arn = aws_kinesis_firehose_delivery_stream.vpc-kinesis-route53-stream-to-splunk.arn
  tags = {
    managed_by_integration = "infra/logging",
    owners                 = "Konflux/infra"
  }
}

resource "aws_route53_resolver_query_log_config_association" "vpc-route53-log-association" {
  for_each                     = { for vpc_id in local.vpc_ids : vpc_id => vpc_id }
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.vpc-route53-query-log-to-splunk.id
  resource_id                  = each.key
}

resource "aws_iam_role" "kinesis_firehose" {
  name        = "vpc-route53-to-splunk-kinesis-firehose"
  description = "IAM Role for Kinesis Firehose to send vpc route53 query logs to splunk"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "vpc-route53-to-splunk-kinesis-firehose"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "s3:AbortMultipartUpload",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
            "s3:PutObject",
          ],
          Resource = [
            data.aws_s3_bucket.vpc-route53-query-log.arn,
            "${data.aws_s3_bucket.vpc-route53-query-log.arn}/*",
          ]
        },
      ]
    })
  }
  tags = merge(
    { Name = "vpc-route53-to-splunk-kinesis-firehose" },
  )
}

module "route53_logs_to_splunk" {
  source                           = "github.com/eisraeli/terraform-aws-vpc-flow-logs-splunk//modules/splunk-firehose-connection?ref=move-to-module-vpc-flow-log-part"
  name                             = local.name
  cloudwatch_log_group_prefix      = "/aws/kinesisfirehose"
  cloudwatch_log_retention         = var.cloudwatch_log_retention
  firehose_splunk_retry_duration   = var.firehose_splunk_retry_duration
  hec_acknowledgment_timeout       = var.hec_acknowledgment_timeout
  hec_token                        = var.hec_token
  kinesis_firehose_buffer          = var.kinesis_firehose_buffer
  kinesis_firehose_buffer_interval = var.kinesis_firehose_buffer_interval
  log_group_tags                   = var.log_group_tags
  log_stream_name                  = var.log_stream_name
  s3_backup_mode                   = var.s3_backup_mode
  s3_compression_format            = var.s3_compression_format
  s3_prefix                        = var.s3_prefix
  splunk_endpoint                  = var.splunk_endpoint
  tags                             = var.tags
}
