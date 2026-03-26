provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "student_data_bucket" {
  bucket = "ims-christ-university-data"
}

resource "aws_s3_bucket_versioning" "student_bucket_versioning" {
  bucket = aws_s3_bucket.student_data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "student_bucket_encryption" {
  bucket = aws_s3_bucket.student_data_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "student_data_access" {
  bucket = aws_s3_bucket.student_data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "student_bucket_logging" {
  bucket        = aws_s3_bucket.student_data_bucket.id
  target_bucket = aws_s3_bucket.student_data_bucket.id
  target_prefix = "logs/"
}
