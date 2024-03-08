# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Locals                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
# locals {
#   s3_iam_roles = flatten([
#     for key, value in var.aws.resources.s3 :
#     [
#       for role_key, role in value.iam_role :
#       {
#         s3_key   = key
#         role_key = role_key
#         role     = role 
#       }
#     ]
#   ])
# }

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_iam_policy_document" "s3-bucket" {
  for_each = var.aws.resources.s3
  dynamic "statement" {
    for_each = each.value.bucket_policy_statements
    content {
      effect    = statement.value.effect
      actions   = [for action in statement.value.actions : action]
      resources = ["arn:aws:s3:::${local.translation_regions[var.aws.region]}-${var.aws.profile}-bucket-${each.key}${statement.value.prefix}"]
      principals {
        type        = statement.value.principal_type
        identifiers = [for role in statement.value.iam_role : "${aws_iam_role.this[role].arn}"]
      }
    }
  }
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
module "s3" {
  source        = "terraform-aws-modules/s3-bucket/aws"
  version       = "3.14.1"
  for_each      = var.aws.resources.s3
  bucket        = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-bucket-${each.key}"
  force_destroy = each.value.force_destroy
  tags          = merge(local.common_tags, each.value.tags)
  versioning    = each.value.versioning

  # Enable if necessary
  # object_lock_enabled       = length(each.value.object_lock_configuration) == 0 ? false : true
  # object_lock_configuration = each.value.object_lock_configuration

  attach_policy = length(each.value.bucket_policy_statements) > 0 ? true : false
  policy        = length(each.value.bucket_policy_statements) > 0 ? data.aws_iam_policy_document.s3-bucket[each.key].json : null
}


# resource "aws_iam_role" "s3-bucket" {
#   for_each           = { for k, v in var.aws.resources.s3 : k => v.iam_role }
#   name               = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-iamrole-${each.key}"
#   assume_role_policy = each.value[each.key].assume_role_policy_jsonfile
#   description        = "IAM role for ${each.key}"
#   #tags               = merge(local.common_tags, each.value.tags)
# }



