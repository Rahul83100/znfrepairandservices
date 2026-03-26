provider "aws" {
  region = "ap-south-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-east-1"
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

resource "aws_s3_bucket_lifecycle_configuration" "student_bucket_lifecycle" {
  bucket = aws_s3_bucket.student_data_bucket.id
  rule {
    id     = "archive-old-data"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}

resource "aws_sns_topic" "bucket_notifications" {
  name = "s3-bucket-notifications"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.student_data_bucket.id
  topic {
    topic_arn = aws_sns_topic.bucket_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket" "replica_bucket" {
  provider = aws.replica
  bucket   = "ims-christ-university-data-replica"
}

resource "aws_iam_role" "replication_role" {
  name = "s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_s3_bucket_replication_configuration" "replication" {
  depends_on = [aws_s3_bucket_versioning.student_bucket_versioning]
  bucket     = aws_s3_bucket.student_data_bucket.id
  role       = aws_iam_role.replication_role.arn
  rule {
    id     = "full-replication"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.replica_bucket.arn
      storage_class = "STANDARD"
    }
  }
}
