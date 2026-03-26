provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "student_data_bucket" {
  bucket = "ims-christ-university-data"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "student_bucket_encryption" {
  bucket = aws_s3_bucket.student_data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
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
