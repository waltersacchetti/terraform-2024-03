# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_subnets" "alb_network" {
  for_each = var.aws.resources.alb
  filter {
    name   = "vpc-id"
    values = [module.vpc[each.value.vpc].vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = [for key in each.value.subnets : join(",", ["${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpc-${each.value.vpc}-${key}"])]
  }
}

data "aws_subnets" "nlb_network" {
  for_each = var.aws.resources.nlb
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
module "alb" {
  source                           = "terraform-aws-modules/alb/aws"
  version                          = "8.7.0"
  for_each                         = var.aws.resources.alb
  name                             = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-alb-${each.key}"
  load_balancer_type               = "application"
  internal                         = each.value.internal
  vpc_id                           = module.vpc[each.value.vpc].vpc_id
  enable_cross_zone_load_balancing = each.value.enable_cross_zone_load_balancing
  enable_deletion_protection       = each.value.enable_deletion_protection
  drop_invalid_header_fields       = each.value.drop_invalid_header_fields
  subnets                          = data.aws_subnets.alb_network[each.key].ids
  security_groups                  = each.value.sg != null ? [module.sg[each.value.sg].security_group_id] : null
  tags                             = merge(local.common_tags, each.value.tags)
  lb_tags                          = each.value.lb_tags
  http_tcp_listeners               = each.value.http_tcp_listeners
  https_listeners                  = each.value.https_listeners
  https_listener_rules             = each.value.https_listener_rules
  target_groups = length(each.value.target_groups) == 0 ? [] : [
    for key, value in each.value.target_groups :
    {
      name                   = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-${each.key}-${value.name}"
      backend_protocol       = value.backend_protocol
      backend_port           = value.backend_port
      target_type            = value.target_type
      deregistration_delay   = value.deregistration_delay
      connection_termination = contains(["UDP", "TCP_UDP"], value.backend_protocol) && value.connection_termination == null ? true : value.connection_termination
      preserve_client_ip     = value.preserve_client_ip
      protocol_version       = value.protocol_version
      health_check = value.health_check == null ? { # Default health_check if not set
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        port                = "traffic-port"
        protocol            = "TCP"
        timeout             = 10
        unhealthy_threshold = 2
        } : {
        enabled             = true
        interval            = value.health_check.interval
        path                = value.health_check.path
        matcher             = value.health_check.matcher
        port                = value.health_check.port
        protocol            = value.health_check.protocol
        healthy_threshold   = value.health_check.healthy_threshold
        unhealthy_threshold = value.health_check.unhealthy_threshold
        timeout             = value.health_check.timeout
      }
      targets = value.targets != null ? {
        for key_target, key_value in value.targets : key_target => {
          target_id = value.target_type == "instance" ? module.ec2[key_value.target_id].id : key_value.target_id # We dont have lambdas resources just "ip" or "instance"
          port      = key_value.port
        }
      } : {}
      tags = merge(local.common_tags, value.tags)
    }
  ]
}


module "nlb" {
  source                           = "terraform-aws-modules/alb/aws"
  version                          = "8.7.0"
  for_each                         = var.aws.resources.nlb
  name                             = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-nlb-${each.key}"
  load_balancer_type               = "network"
  internal                         = each.value.internal
  vpc_id                           = module.vpc[each.value.vpc].vpc_id
  enable_cross_zone_load_balancing = each.value.enable_cross_zone_load_balancing
  enable_deletion_protection       = each.value.enable_deletion_protection
  subnets                          = data.aws_subnets.nlb_network[each.key].ids
  security_groups                  = each.value.sg != null ? [module.sg[each.value.sg].security_group_id] : null
  tags                             = merge(local.common_tags, each.value.tags)
  lb_tags                          = each.value.lb_tags
  http_tcp_listeners               = each.value.http_tcp_listeners
  https_listeners                  = each.value.https_listeners
  https_listener_rules             = each.value.https_listener_rules
  target_groups = length(each.value.target_groups) == 0 ? [] : [
    for key, value in each.value.target_groups :
    {
      name                   = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-${each.key}-${value.name}"
      backend_protocol       = value.backend_protocol
      backend_port           = value.backend_port
      target_type            = value.target_type
      deregistration_delay   = value.deregistration_delay
      connection_termination = contains(["UDP", "TCP_UDP"], value.backend_protocol) && value.connection_termination == null ? true : value.connection_termination
      preserve_client_ip     = value.preserve_client_ip
      protocol_version       = value.protocol_version
      health_check = value.health_check == null ? { # Default health_check if not set
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        port                = "traffic-port"
        protocol            = "TCP"
        timeout             = 10
        unhealthy_threshold = 2
        } : {
        enabled             = true
        interval            = value.health_check.interval
        path                = value.health_check.path
        matcher             = value.health_check.matcher
        port                = value.health_check.port
        protocol            = value.health_check.protocol
        healthy_threshold   = value.health_check.healthy_threshold
        unhealthy_threshold = value.health_check.unhealthy_threshold
        timeout             = value.health_check.timeout
      }
      targets = value.targets != null ? {
        for key_target, key_value in value.targets : key_target => {
          target_id = value.target_type == "instance" ? module.ec2[key_value.target_id].id : value.target_type == "alb" ? module.alb[key_value.target_id].lb_arn : key_value.target_id
          port      = key_value.port
        }
      } : {}
      stickiness = value.stickiness == null ? { # Default stickiness if not set
        enabled = false
        type    = "source_ip"
        } : {
        enabled         = true
        type            = value.stickiness.type
        cookie_duration = value.stickiness.cookie_duration
      }
      tags = merge(local.common_tags, value.tags)
    }
  ]
}