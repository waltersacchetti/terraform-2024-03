
locals {
  ec2_list_network_interace = flatten([
    for key, value in var.aws.resources.ec2 : [
      for index, interface in value.network_interfaces : {
        ec2    = key
        vpc    = interface.vpc
        subnet = interface.subnet
        index  = index
        sg     = interface.sg
      }
    ]
  ])
  ec2_map_network_interface = {
    for interface in local.ec2_list_network_interace : "${interface.ec2}_${interface.index}" => interface
  }

  ec2_list_block_device_mappings = flatten([
    for key, value in var.aws.resources.ec2 : [
      for ebs_key, ebs_value in value.ebs_block_device : {
        ec2         = key
        device_name = ebs_key
        encrypted   = ebs_value.encrypted
        type        = ebs_value.type
        size        = ebs_value.size
        kms_key_id  = ebs_value.kms_key_id
        throughput  = ebs_value.throughput
        iops        = ebs_value.iops
        tags        = ebs_value.tags
      }
    ]
  ])

  ec2_map_block_device_mappings = {
    for value in local.ec2_list_block_device_mappings : "${value.ec2}_${value.device_name}" => value
  }
}



# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_subnets" "ec2_network" {
  for_each = { for k, v in var.aws.resources.ec2 : k => v if v.subnet != null }
  filter {
    name   = "vpc-id"
    values = [module.vpc[each.value.vpc].vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpc-${each.value.vpc}-${each.value.subnet}"]
  }
}

data "aws_subnets" "ec2_network_interfaces" {
  for_each = local.ec2_map_network_interface
  filter {
    name   = "vpc-id"
    values = [module.vpc[each.value.vpc].vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpc-${each.value.vpc}-${each.value.subnet}"]
  }
}

data "aws_ami" "amazon-linux-2" {
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
resource "tls_private_key" "ec2_key" {
  for_each  = var.aws.resources.ec2
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ec2-key" {
  for_each        = var.aws.resources.ec2
  content         = tls_private_key.ec2_key[each.key].private_key_pem
  filename        = "data/${terraform.workspace}/ec2/${each.key}/${local.translation_regions[var.aws.region]}-${var.aws.profile}-key-pair-${each.key}.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "this" {
  for_each   = var.aws.resources.ec2
  key_name   = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-key-pair-${each.key}"
  public_key = tls_private_key.ec2_key[each.key].public_key_openssh
  tags       = merge(local.common_tags, each.value.key_pair_tags)
}

resource "aws_network_interface" "this" {
  for_each        = local.ec2_map_network_interface
  subnet_id       = element(data.aws_subnets.ec2_network_interfaces[each.key].ids, 0)
  security_groups = [module.sg[each.value.sg].security_group_id]
}

module "ec2" {
  source        = "terraform-aws-modules/ec2-instance/aws"
  version       = "5.5.0"
  for_each      = var.aws.resources.ec2
  name          = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-ec2-${each.key}"
  instance_type = each.value.instance_type
  ami           = each.value.ami == null ? data.aws_ami.amazon-linux-2.id : each.value.ami
  key_name      = aws_key_pair.this[each.key].key_name
  monitoring    = each.value.monitoring

  vpc_security_group_ids = length(each.value.network_interfaces) == 0 ? [module.sg[each.value.sg].security_group_id] : null
  subnet_id              = length(each.value.network_interfaces) == 0 ? data.aws_subnets.ec2_network[each.key].ids[0] : null

  user_data_base64            = each.value.user_data != null ? base64encode(each.value.user_data) : null
  user_data_replace_on_change = each.value.user_data_replace_on_change
  enable_volume_tags          = false
  tags                        = merge(local.common_tags, each.value.tags)
  create_iam_instance_profile = true
  iam_role_description        = "IAM role for ${local.translation_regions[var.aws.region]}-${var.aws.profile}-ec2-${each.key}"
  iam_role_policies = each.value.iam_role_policies != null ? {
    for key, value in each.value.iam_role_policies :
    key => strcontains(value, "arn:aws") ? value : aws_iam_policy.this[value].arn
    } : {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  root_block_device = [
    {
      delete_on_termination = each.value.root_block_device.delete_on_termination
      encrypted             = each.value.root_block_device.encrypted
      kms_key_id            = each.value.root_block_device.encrypted == false || each.value.root_block_device.kms_key_id == null ? null : module.kms[each.value.root_block_device.kms_key_id].key_arn
      iops                  = each.value.root_block_device.iops
      volume_type           = each.value.root_block_device.volume_type
      throughput            = each.value.root_block_device.throughput
      volume_size           = each.value.root_block_device.volume_size
      tags                  = merge({ "Instance" = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-ec2-${each.key}" }, local.common_tags, each.value.root_block_device.tags)
    }
  ]
  network_interface = length(each.value.network_interfaces) == 0 ? [] : [
    for index, value in each.value.network_interfaces :
    {
      device_index          = index
      network_interface_id  = aws_network_interface.this["${each.key}_${index}"].id
      delete_on_termination = false
    }
  ]
}

resource "aws_volume_attachment" "this" {
  for_each    = local.ec2_map_block_device_mappings
  device_name = "/dev/${each.value.device_name}"
  volume_id   = aws_ebs_volume.this[each.key].id
  instance_id = module.ec2[each.value.ec2].id
}

resource "aws_ebs_volume" "this" {
  for_each          = local.ec2_map_block_device_mappings
  availability_zone = module.ec2[each.value.ec2].availability_zone
  encrypted         = each.value.encrypted
  kms_key_id        = each.value.encrypted == false || each.value.kms_key_id == null ? null : module.kms[each.value.kms_key_id].key_arn
  iops              = each.value.iops
  type              = each.value.type
  throughput        = each.value.throughput
  size              = each.value.size
  tags              = merge({ "Instance" = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-ec2-${each.value.ec2}" }, local.common_tags, each.value.tags)
}