resource "aws_s3_bucket" "student_data_bucket" {
  bucket = "ims-christ-university-data"
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }
}