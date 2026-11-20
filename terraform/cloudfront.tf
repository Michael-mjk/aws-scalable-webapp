# ---------------------------------------------------------------------------
# Private S3 bucket for static assets (only CloudFront can read it)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "static" {
  bucket        = "${local.name}-static-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # learning project: let `terraform destroy` empty it
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "static" {
  bucket = aws_s3_bucket.static.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id
  versioning_configuration {
    status = "Enabled"
  }
}

locals {
  static_dir = "${path.module}/../app/static"
  mime_types = {
    css   = "text/css"
    js    = "application/javascript"
    svg   = "image/svg+xml"
    png   = "image/png"
    jpg   = "image/jpeg"
    ico   = "image/x-icon"
    woff2 = "font/woff2"
  }
}

resource "aws_s3_object" "static" {
  for_each = fileset(local.static_dir, "**")

  bucket        = aws_s3_bucket.static.id
  key           = "static/${each.value}"
  source        = "${local.static_dir}/${each.value}"
  etag          = filemd5("${local.static_dir}/${each.value}")
  content_type  = lookup(local.mime_types, regex("[^.]+$", each.value), "application/octet-stream")
  cache_control = "public, max-age=86400"
}

# ---------------------------------------------------------------------------
# CloudFront distribution with Origin Access Control (OAC)
# ---------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${local.name}-static-oac"
  description                       = "CloudFront -> S3 static assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "static" {
  enabled         = true
  comment         = "${local.name} static assets"
  price_class     = "PriceClass_100" # North America + Europe edges (cheapest)
  http_version    = "http2and3"
  is_ipv6_enabled = true

  origin {
    origin_id                = "s3-static"
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-static"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Bucket policy: allow reads ONLY from this specific distribution
data "aws_iam_policy_document" "static_bucket" {
  statement {
    sid       = "AllowCloudFrontOAC"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.static.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.static.arn, "${aws_s3_bucket.static.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "static" {
  bucket     = aws_s3_bucket.static.id
  policy     = data.aws_iam_policy_document.static_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.static]
}
