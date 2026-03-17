# --- S3 Storage (alternative to RustFS) ---
#
# When enabled, creates S3 buckets and IRSA roles for registry, loki,
# and mimir. The cabotage module annotates service accounts with the
# role ARNs so pods authenticate via the AWS SDK credential chain.

locals {
  s3_services = var.enable_s3_storage ? {
    registry = {
      bucket_name     = "${var.s3_bucket_prefix}-registry"
      service_account = "registry"
      namespace       = "cabotage"
    }
    loki = {
      bucket_name     = "${var.s3_bucket_prefix}-loki"
      service_account = "resident-loki"
      namespace       = "cabotage"
    }
    mimir = {
      bucket_name     = "${var.s3_bucket_prefix}-mimir"
      service_account = "resident-mimir"
      namespace       = "cabotage"
    }
  } : {}
}

# --- Buckets ---

resource "aws_s3_bucket" "storage" {
  for_each = local.s3_services

  bucket = each.value.bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "storage" {
  for_each = local.s3_services

  bucket                  = aws_s3_bucket.storage[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  for_each = local.s3_services

  bucket = aws_s3_bucket.storage[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- IRSA Roles ---

module "s3_irsa" {
  for_each = local.s3_services

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-${each.key}-s3"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${each.value.namespace}:${each.value.service_account}"]
    }
  }

  tags = local.tags
}

resource "aws_iam_role_policy" "s3_storage" {
  for_each = local.s3_services

  name = "${each.key}-bucket-access"
  role = module.s3_irsa[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
        ]
        Resource = [aws_s3_bucket.storage[each.key].arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
        ]
        Resource = ["${aws_s3_bucket.storage[each.key].arn}/*"]
      },
    ]
  })
}
