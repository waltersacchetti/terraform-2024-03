# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_iam_policy_document" "assume_role_policy" {
  for_each = { for k, v in var.aws.resources.iam : k => v if v.create_iam_role == true }
  statement {
    effect  = each.value.iam_role.assume_role_policy.effect
    actions = [for action in each.value.iam_role.assume_role_policy.actions : action]
    principals {
      type        = each.value.iam_role.assume_role_policy.principal_type
      identifiers = [for idt in each.value.iam_role.assume_role_policy.identifiers : idt]
    }
  }
}

data "aws_iam_policy_document" "this" {
  for_each = { for k, v in var.aws.resources.iam : k => v if v.create_iam_policy == true }
  dynamic "statement" {
    for_each = each.value.iam_policy.policies
    content {
      effect    = statement.value.effect
      actions   = [for action in statement.value.actions : action]
      resources = [for resource in statement.value.resources : resource]
    }
  }
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
resource "aws_iam_role" "this" {
  for_each           = { for k, v in var.aws.resources.iam : k => v if v.create_iam_role == true }
  name               = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-iam-role-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy[each.key].json
  description        = "IAM role for ${each.key}"
  tags               = merge(local.common_tags, each.value.iam_role.tags)
}

resource "aws_iam_policy" "this" {
  for_each = { for k, v in var.aws.resources.iam : k => v if v.create_iam_policy == true }
  name     = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-iam-policy-${each.key}"
  policy   = data.aws_iam_policy_document.this[each.key].json
  tags     = merge(local.common_tags, each.value.iam_policy.tags)
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = { for k, v in var.aws.resources.iam : k => v if v.create_iam_role_policy_attachment == true }
  policy_arn = aws_iam_policy.this[each.value.iam_role_policy_attachment.iam_policy].arn
  role       = aws_iam_role.this[each.value.iam_role_policy_attachment.role].name
}

resource "aws_iam_instance_profile" "this" {
  for_each = { for k, v in var.aws.resources.iam : k => v if v.create_iam_instance_profile == true }
  name     = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-iam-instance-profile-${each.key}"
  role     = aws_iam_role.this[each.value.iam_instance_profile.role].name
  tags     = merge(local.common_tags, each.value.iam_instance_profile.tags)
}