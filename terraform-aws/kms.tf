module "kms" {
  source                                 = "terraform-aws-modules/kms/aws"
  version                                = "2.0.1"
  for_each                               = var.aws.resources.kms
  deletion_window_in_days                = each.value.deletion_window_in_days
  description                            = "Customer managed key for ${each.key}"
  enable_key_rotation                    = each.value.enable_key_rotation
  is_enabled                             = true
  key_usage                              = each.value.key_usage
  multi_region                           = false
  enable_default_policy                  = true
  key_owners                             = each.value.key_owners
  key_administrators                     = each.value.key_administrators
  key_users                              = each.value.key_users
  key_service_users                      = each.value.key_service_users
  key_service_roles_for_autoscaling      = each.value.key_service_roles_for_autoscaling
  key_symmetric_encryption_users         = each.value.key_symmetric_encryption_users
  key_hmac_users                         = each.value.key_hmac_users
  key_asymmetric_public_encryption_users = each.value.key_asymmetric_public_encryption_users
  key_asymmetric_sign_verify_users       = each.value.key_asymmetric_sign_verify_users
  key_statements                         = each.value.key_statements
  aliases                                = each.value.aliases
  computed_aliases                       = each.value.computed_aliases
  aliases_use_name_prefix                = false
  grants                                 = each.value.grants
  tags                                   = merge(local.common_tags, each.value.tags)
}