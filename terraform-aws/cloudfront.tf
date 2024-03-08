# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_cloudfront_cache_policy" "managed-cachingdisabled" {
  name = "Managed-CachingDisabled"
  #id -> 4135ea2d-6df8-44a3-9df3-4b5a84be39ad
}

data "aws_cloudfront_origin_request_policy" "managed-allviewer" {
  name = "Managed-AllViewer"
  #id -> 216adef6-5c7f-47e4-b989-5492eafa07d3
}

data "aws_cloudfront_response_headers_policy" "managed-cors-with-preflight" {
  name = "Managed-CORS-With-Preflight"
  #id -> 5cc3b908-e619-4b99-88e5-2cf7f45965bd
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
resource "aws_cloudfront_distribution" "this" {
  for_each     = var.aws.resources.cloudfront_distributions
  enabled      = each.value.enabled
  http_version = each.value.http_version
  tags         = merge(local.common_tags, each.value.tags)
  #web_acl_id     = each.value.web_acl_id #Or reference to another resource creat
  default_cache_behavior {
    allowed_methods            = each.value.default_cache_behavior.allowed_methods
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed-cachingdisabled.id
    cached_methods             = each.value.default_cache_behavior.cached_methods
    compress                   = each.value.default_cache_behavior.compress
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.managed-allviewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed-cors-with-preflight.id
    target_origin_id           = "KVS-${local.translation_regions[var.aws.region]}-${each.key}"
    viewer_protocol_policy     = each.value.default_cache_behavior.viewer_protocol_policy
  }
  origin {
    domain_name = each.value.origin.domain_name
    origin_id   = "KVS-${local.translation_regions[var.aws.region]}-${each.key}"
    custom_origin_config {
      http_port              = each.value.origin.custom_origin_config.http_port
      https_port             = each.value.origin.custom_origin_config.https_port
      origin_protocol_policy = each.value.origin.custom_origin_config.origin_protocol_policy
      origin_ssl_protocols   = each.value.origin.custom_origin_config.origin_ssl_protocols
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = each.value.restrictions.restriction_type
      locations        = each.value.restrictions.locations
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = each.value.viewer_certificate.cloudfront_default_certificate #acm_certificate_arn, cloudfront_default_certificate, iam_certificate_id, minimum_protocol_version, ssl_support_method
    minimum_protocol_version       = each.value.viewer_certificate.minimum_protocol_version
  }

  #logging_config {
  #  bucket         =  each.value.logging_config.bucket
  #  include_cookies = each.value.logging_config.include_cookies
  #}

  dynamic "ordered_cache_behavior" {
    for_each = each.value.ordered_cache_behavior
    content {
      allowed_methods            = ordered_cache_behavior.value.allowed_methods
      cache_policy_id            = aws_cloudfront_cache_policy.this[ordered_cache_behavior.value.cache_policy_id].id #data.aws_cloudfront_cache_policy.custom_cache_policy[ordered_cache_behavior.value.cache_policy_id].id
      cached_methods             = ordered_cache_behavior.value.cached_methods
      compress                   = ordered_cache_behavior.value.compress
      path_pattern               = ordered_cache_behavior.value.path_pattern
      response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed-cors-with-preflight.id #ordered_cache_behavior.value.response_headers_policy_id
      target_origin_id           = "KVS-${local.translation_regions[var.aws.region]}-${each.key}"
      viewer_protocol_policy     = ordered_cache_behavior.value.viewer_protocol_policy
    }
  }
  depends_on = [aws_cloudfront_cache_policy.this]
}


resource "aws_cloudfront_cache_policy" "this" {
  for_each    = var.aws.resources.cloudfront_cache_policies
  default_ttl = each.value.default_ttl
  max_ttl     = each.value.max_ttl
  min_ttl     = each.value.min_ttl
  name        = each.value.name
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = each.value.parameters_in_cache_key_and_forwarded_to_origin.enable_accept_encoding_brotli
    enable_accept_encoding_gzip   = each.value.parameters_in_cache_key_and_forwarded_to_origin.enable_accept_encoding_gzip
    cookies_config {
      cookie_behavior = each.value.parameters_in_cache_key_and_forwarded_to_origin.cookies_config.cookie_behavior

      # Commented setting this property is not necessary
      # cookies {
      #   items = each.value.parameters_in_cache_key_and_forwarded_to_origin.cookies_config.cookies
      # }
    }
    headers_config {
      header_behavior = each.value.parameters_in_cache_key_and_forwarded_to_origin.headers_config.header_behavior

      # Commented setting this property is not necessary
      # headers {
      #   items = each.value.parameters_in_cache_key_and_forwarded_to_origin.headers_config.headers
      # }
    }
    query_strings_config {
      query_string_behavior = each.value.parameters_in_cache_key_and_forwarded_to_origin.query_strings_config.query_string_behavior

      # dynamic, since setting the query_strings with no values change the state of the resource in each plan/apply
      dynamic "query_strings" {
        for_each = each.value.parameters_in_cache_key_and_forwarded_to_origin.query_strings_config.enable_query_strings ? [each.value.parameters_in_cache_key_and_forwarded_to_origin.query_strings_config] : []

        content {
          items = query_strings.value.query_strings
        }
      }
    }
  }
}
