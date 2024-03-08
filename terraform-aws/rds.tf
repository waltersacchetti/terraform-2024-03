# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Locals                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
locals {
  translation_rds_ports = {
    aurora   = 3306
    mysql    = 3306
    postgres = 5432
  }

  rds_list_postgres_databases = flatten([
    for key, value in var.aws.resources.rds : [
      value.engine == "postgres" && length(value.databases) > 0 ? [
        for database in concat(value.databases, [key]) : {
          rds  = key
          name = database
        }
        ] : [
        {
          rds  = key
          name = key
        }
      ]
    ]
  ])

  rds_map_postgres_databases = {
    for database in local.rds_list_postgres_databases : "${database.rds}_${database.name}" => database
  }
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
resource "random_password" "rds" {
  for_each         = var.aws.resources.rds
  length           = 16
  special          = true
  upper            = true
  lower            = true
  number           = true
  override_special = "-_."
}

module "rds" {
  source     = "terraform-aws-modules/rds/aws"
  version    = "6.1.0"
  for_each   = var.aws.resources.rds
  tags       = merge(local.common_tags, each.value.tags)
  identifier = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-rds-${each.key}"

  db_subnet_group_name   = module.vpc[each.value.vpc].database_subnet_group
  create_db_subnet_group = each.value.create_db_subnet_group
  vpc_security_group_ids = [module.sg[each.value.sg].security_group_id]

  engine               = each.value.engine
  engine_version       = each.value.engine_version
  family               = each.value.family
  major_engine_version = each.value.major_engine_version

  instance_class    = each.value.instance_class
  allocated_storage = each.value.allocated_storage

  db_name                             = each.value.db_name
  username                            = each.value.username
  manage_master_user_password         = false
  password                            = each.value.password == null || each.value.password == "" ? random_password.rds[each.key].result : each.value.password
  port                                = each.value.port != null ? each.value.port : local.translation_rds_ports[each.value.engine]
  iam_database_authentication_enabled = each.value.iam_db_auth_enabled

  #Maintenance
  maintenance_window      = each.value.maintenance_window
  backup_window           = each.value.backup_window
  backup_retention_period = each.value.backup_retention_period
  deletion_protection     = each.value.deletion_protection

  #AZ
  availability_zone = each.value.multi_az == false ? module.vpc[each.value.vpc].azs[0] : null
  multi_az          = each.value.multi_az

  publicly_accessible = each.value.publicly_accessible
}

resource "random_password" "rds_postgres_db" {
  for_each         = local.rds_map_postgres_databases
  length           = 16
  special          = true
  upper            = true
  lower            = true
  number           = true
  override_special = "-_."
}

resource "null_resource" "rds_postgres_db" {
  depends_on = [module.rds, random_password.rds_postgres_db]
  for_each   = local.rds_map_postgres_databases
  provisioner "local-exec" {
    command = templatefile("${path.module}/templates/rds-postgresql-create.tftpl", {
      host     = "postgresql://${module.rds[each.value.rds].db_instance_username}:${var.aws.resources.rds[each.value.rds].password == null || var.aws.resources.rds[each.value.rds].password == "" ? random_password.rds[each.value.rds].result : var.aws.resources.rds[each.value.rds].password}@${module.rds[each.value.rds].db_instance_endpoint}/${var.aws.resources.rds[each.value.rds].db_name == null ? each.value.rds : var.aws.resources.rds[each.value.rds].db_name}"
      username = each.value.name
      password = random_password.rds_postgres_db[each.key].result
    })
  }
}
