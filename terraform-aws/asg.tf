# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_subnets" "asg_network" {
  for_each = var.aws.resources.asg
  filter {
    name   = "vpc-id"
    values = [module.vpc[each.value.vpc].vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = [for key in each.value.subnets : join(",", ["${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpc-${each.value.vpc}-${key}"])]
  }
}

data "aws_ami" "asg-amazon-linux-2" {
  owners = ["amazon"]
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }

  most_recent = true
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
module "asg" {
  source                      = "terraform-aws-modules/autoscaling/aws"
  version                     = "6.10.0"
  for_each                    = var.aws.resources.asg
  name                        = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-asg-${each.key}"
  min_size                    = each.value.min_size
  max_size                    = each.value.max_size
  desired_capacity            = each.value.desired_capacity
  health_check_type           = each.value.health_check_type
  vpc_zone_identifier         = data.aws_subnets.asg_network[each.key].ids
  image_id                    = each.value.image_id == null ? data.aws_ami.asg-amazon-linux-2.id : each.value.image_id
  instance_type               = each.value.instance_type
  ebs_optimized               = each.value.ebs_optimized
  enable_monitoring           = each.value.enable_monitoring
  create_iam_instance_profile = true
  update_default_version      = each.value.update_default_version
  instance_refresh            = each.value.instance_refresh
  iam_role_policies = each.value.iam_role_policies != null ? {
    for key, value in each.value.iam_role_policies :
    key => strcontains(value, "arn:aws") ? value : aws_iam_policy.this[value].arn
    } : {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  iam_role_name            = "iam-role-${local.translation_regions[var.aws.region]}-${var.aws.profile}-asg-${each.key}"
  iam_role_use_name_prefix = true
  block_device_mappings = length(each.value.block_device_mappings) == 0 ? [] : [
    for key, value in each.value.block_device_mappings :
    {
      device_name = value.device_name
      no_device   = key
      ebs = value.ebs != null ? {
        delete_on_termination = value.ebs.delete_on_termination
        encrypted             = value.ebs.encrypted
        kms_key_id            = value.ebs.encrypted == false || value.ebs.kms_key_id == null ? null : module.kms[value.ebs.kms_key_id].key_arn
        throughput            = value.ebs.throughput
        iops                  = value.ebs.iops
        volume_size           = value.ebs.volume_size
        volume_type           = value.ebs.volume_type
      } : null
    }
  ]
  metadata_options = each.value.metadata_options
  network_interfaces = length(each.value.network_interfaces) == 0 ? [] : [
    for key, value in each.value.network_interfaces :
    {
      delete_on_termination = value.delete_on_termination
      description           = value.description
      device_index          = key
      security_groups       = [for value in value.security_groups : module.sg[value].security_group_id]
    }
  ]
  user_data = base64encode(each.value.user_data_script)
  target_group_arns = each.value.target_groups == null ? [] : flatten([
    for tg_name in each.value.target_groups.target_group_names :
    each.value.target_groups.load_balancer_type == "alb" ? [
      for arn in module.alb[each.value.target_groups.load_balancer_key].target_group_arns : arn if strcontains(arn, "${local.translation_regions[var.aws.region]}-${var.aws.profile}-${each.value.target_groups.load_balancer_key}-${tg_name}")
      ] : [
      for arn in module.nlb[each.value.target_groups.load_balancer_key].target_group_arns : arn if strcontains(arn, "${local.translation_regions[var.aws.region]}-${var.aws.profile}-${each.value.target_groups.load_balancer_key}-${tg_name}")
    ]
  ])
  tags = merge(local.common_tags, each.value.tags)
}