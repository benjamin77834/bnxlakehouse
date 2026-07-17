# =============================================================================
# S3 - Buckets para documentos del chatbot
# =============================================================================

# Bucket para PDFs iniciales (documentos que el chatbot conoce)
resource "aws_s3_bucket" "documents" {
  bucket = "${var.project_name}-documents-${var.environment}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Carpetas iniciales para organizar documentos
resource "aws_s3_object" "folders" {
  for_each = toset(["pdfs/", "data-lake/", "otros/"])
  bucket   = aws_s3_bucket.documents.id
  key      = each.value
  content  = ""
}
