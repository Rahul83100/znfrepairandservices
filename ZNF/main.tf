provider "aws" {
  region = "ap-south-1"
}

# VULNERABILITY: This S3 bucket has no encryption and no logging enabled!
resource "aws_s3_bucket" "student_data_bucket" {
  bucket = "ims-christ-university-data"
}
