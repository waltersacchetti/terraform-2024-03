# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
resource "aws_wafv2_web_acl" "this" {
  for_each    = var.aws.resources.waf
  name        = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-waf-${each.key}"
  description = "Web ACL for ${local.translation_regions[var.aws.region]}-${var.aws.profile}-waf-${each.key}"
  scope       = each.value.scope
  tags        = merge(local.common_tags, each.value.tags)

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = each.value.visibility_config.cloudwatch_metrics_enabled
    metric_name                = "WAF-Metrics-${each.key}"
    sampled_requests_enabled   = each.value.visibility_config.sampled_requests_enabled
  }

  dynamic "rule" {
    for_each = each.value.rules
    content {
      name     = rule.key
      priority = rule.value.priority

      # Add other attributes from the map if needed
      statement {
        managed_rule_group_statement {
          name        = rule.value.statement.name
          vendor_name = rule.value.statement.vendor_name
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = rule.value.visibility_config.cloudwatch_metrics_enabled
        metric_name                = "${rule.key}-Metrics"
        sampled_requests_enabled   = rule.value.visibility_config.sampled_requests_enabled
      }

      override_action {
        none {}
      }
    }
  }
}