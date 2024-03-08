# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Locals                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
locals {
  aws_subnet_public = var.aws.resources.alternat.vpc == null ? {} : {
    for az in module.vpc[var.aws.resources.alternat.vpc].azs : az => flatten([
      for subnet in data.aws_subnet.public_subnets : compact([subnet.availability_zone == az ? subnet.id : null])
    ])
  }
  aws_subnet_private = var.aws.resources.alternat.vpc == null ? {} : {
    for az in module.vpc[var.aws.resources.alternat.vpc].azs : az => flatten([
      for subnet in data.aws_subnet.private_subnets : compact([subnet.availability_zone == az ? subnet.id : null])
    ])
  }

  aws_maps_private_subnets = var.aws.resources.alternat.vpc == null ? {} : {
    for subnet in data.aws_subnet.private_subnets : subnet.id => subnet.availability_zone
  }

  aws_routes_private = var.aws.resources.alternat.vpc == null ? {} : {
    for az in module.vpc[var.aws.resources.alternat.vpc].azs : az => flatten([
      for route in data.aws_route_table.router_tables : compact([local.aws_maps_private_subnets[route.subnet_id] == az ? route.id : null])
    ])
  }

  alternat_vpc = var.aws.resources.alternat.vpc == null ? null : module.vpc[var.aws.resources.alternat.vpc]
  alternat_vpc_az_maps = local.alternat_vpc == null ? [] : [
    for az in module.vpc[var.aws.resources.alternat.vpc].azs : {
      az                 = az
      route_table_ids    = local.aws_routes_private[az]
      public_subnet_id   = local.aws_subnet_public[az][0]
      private_subnet_ids = local.aws_subnet_private[az]
    }
  ]
}
# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_subnet" "private_subnets" {
  count = var.aws.resources.alternat.vpc == null ? 0 : length(module.vpc[var.aws.resources.alternat.vpc].private_subnets)
  id    = module.vpc[var.aws.resources.alternat.vpc].private_subnets[count.index]
}


data "aws_subnet" "public_subnets" {
  count = var.aws.resources.alternat.vpc == null ? 0 : length(module.vpc[var.aws.resources.alternat.vpc].public_subnets)
  id    = module.vpc[var.aws.resources.alternat.vpc].public_subnets[count.index]
}

data "aws_route_table" "router_tables" {
  for_each  = local.aws_maps_private_subnets
  vpc_id    = module.vpc[var.aws.resources.alternat.vpc].vpc_id
  subnet_id = each.key
}


# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
module "alternat_instances" {
  count                      = var.aws.resources.alternat.vpc == null ? 0 : 1
  source                     = "git::https://github.com/1debit/alternat.git//modules/terraform-aws-alternat?ref=v0.4.4"
  alternat_image_uri         = var.aws.resources.alternat.image_uri
  alternat_image_tag         = var.aws.resources.alternat.image_tag
  nat_instance_type          = var.aws.resources.alternat.instance_type
  lambda_package_type        = var.aws.resources.alternat.lambda_package_type
  ingress_security_group_ids = flatten([for sg in var.aws.resources.alternat.sgs : module.sg[sg].security_group_id])
  max_instance_lifetime      = var.aws.resources.alternat.max_instance_lifetime

  # Optional EBS volume settings. If omitted, the AMI defaults will be used.
  nat_instance_block_devices = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        encrypted   = true
        volume_type = "gp3"
        volume_size = 20
      }
    }
  }

  vpc_id      = module.vpc[var.aws.resources.alternat.vpc].vpc_id
  vpc_az_maps = local.alternat_vpc_az_maps
}