# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_subnets" "mq_network" {
  for_each = var.aws.resources.mq
  filter {
    name   = "vpc-id"
    values = [module.vpc[each.value.vpc].vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = [for key in each.value.subnets : join(",", ["${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpc-${each.value.vpc}-${key}"])]
  }
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
resource "aws_mq_configuration" "this" {
  for_each       = var.aws.resources.mq
  name           = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-mq-config-${each.key}"
  engine_type    = each.value.engine_type
  engine_version = each.value.engine_version
  tags           = merge(local.common_tags, each.value.tags)
  data           = each.value.configuration
}

resource "random_password" "mq" {
  for_each         = var.aws.resources.mq
  length           = 16
  special          = true
  upper            = true
  lower            = true
  number           = true
  override_special = "-_."
}

resource "aws_mq_broker" "this" {
  for_each    = var.aws.resources.mq
  tags        = merge(local.common_tags, each.value.tags)
  broker_name = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-mq-${each.key}"
  configuration {
    id       = aws_mq_configuration.this[each.key].id
    revision = aws_mq_configuration.this[each.key].latest_revision
  }
  engine_type        = each.value.engine_type
  engine_version     = each.value.engine_version
  host_instance_type = each.value.host_instance_type
  security_groups    = [module.sg[each.value.sg].security_group_id]
  subnet_ids         = data.aws_subnets.mq_network[each.key].ids
  deployment_mode    = each.value.deployment_mode
  user {
    username       = each.value.username
    password       = each.value.password == null || each.value.password == "" ? random_password.mq[each.key].result : each.value.password
    console_access = true
  }
}