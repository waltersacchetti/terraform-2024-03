# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
resource "aws_kinesis_video_stream" "this" {
  for_each                = var.aws.resources.kinesis
  name                    = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-kinesis-${each.key}"
  data_retention_in_hours = each.value.data_retention_in_hours
  device_name             = "kinesis-video-${var.aws.region}-${var.aws.profile}-${each.key}"
  media_type              = each.value.media_type
  tags                    = merge(local.common_tags, each.value.tags)
}