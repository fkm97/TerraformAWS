terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.40" }
  }
}

provider "aws" {
  region  = "us-east-1"
}

locals {
  bucket_name = "assignmentbucket2025082701-tfscript"
}

# ----------------------- S3 bucket (private) -----------------------
resource "aws_s3_bucket" "bucket" { bucket = local.bucket_name }

resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "own" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enc" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ----------------------- CloudFront (OAC) -----------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "oac-${local.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled = true

  origin {
    domain_name              = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id                = "s3-${local.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    s3_origin_config {
      origin_access_identity = ""
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-${local.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate { cloudfront_default_certificate = true }
}

# ----------------------- Bucket policy: CF-only reads -----------------------
resource "aws_s3_bucket_policy" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowCloudFrontServiceRead",
        Effect    = "Allow",
        Principal = { Service = "cloudfront.amazonaws.com" },
        Action    = "s3:GetObject",
        Resource  = "arn:aws:s3:::${local.bucket_name}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      },
      {
        Sid       = "DenyNonCloudFrontRead",
        Effect    = "Deny",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "arn:aws:s3:::${local.bucket_name}/*",
        Condition = {
          StringNotEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
  depends_on = [aws_s3_bucket_ownership_controls.own, aws_cloudfront_distribution.cdn]
}

# ----------------------- EC2 role: write-only to env prefixes -----------------------
resource "aws_iam_role" "ec2_s3_uploader_tf" {
  name               = "EC2-S3-Uploader-TF"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_write_envs_tf" {
  name   = "S3WriteOnly-EnvPrefixes-TF"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid     = "WriteEnvPrefixes",
        Effect  = "Allow",
        Action  = ["s3:PutObject", "s3:AbortMultipartUpload"],
        Resource = [
          "arn:aws:s3:::${local.bucket_name}/dev/*",
          "arn:aws:s3:::${local.bucket_name}/qa/*",
          "arn:aws:s3:::${local.bucket_name}/prod/*"
        ],
        Condition = { Bool = { "aws:SecureTransport" = true } }
      },
      {
        Sid      = "ListByPrefix",
        Effect   = "Allow",
        Action   = "s3:ListBucket",
        Resource = "arn:aws:s3:::${local.bucket_name}",
        Condition = { StringLike = { "s3:prefix" = ["dev/*", "qa/*", "prod/*"] } }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_tf" {
  role       = aws_iam_role.ec2_s3_uploader_tf.name
  policy_arn = aws_iam_policy.s3_write_envs_tf.arn
}

resource "aws_iam_instance_profile" "profile_tf" {
  name = "EC2-S3-Uploader-TF"
  role = aws_iam_role.ec2_s3_uploader_tf.name
}

# ----------------------- EC2 (fixed AMI) -----------------------
variable "key_name" {
  description = "Existing EC2 key pair name (set if you want SSH)"
  type        = string
  default     = null
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH"
  type        = string
  default     = "0.0.0.0/0"
}

data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "ec2" {
  name        = "allow-ssh-for-uploader-tf"
  description = "Allow SSH for testing uploads"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_instance" "uploader" {
  ami                    = "ami-00ca32bbc84273381"   
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.profile_tf.name
  key_name               = var.key_name

  tags = { Name = "s3-uploader-tf" }
}

# ----------------------- Outputs -----------------------
output "bucket_name"       { value = aws_s3_bucket.bucket.bucket }
output "cloudfront_domain" { value = aws_cloudfront_distribution.cdn.domain_name }
output "instance_profile"  { value = aws_iam_instance_profile.profile_tf.name }
output "iam_role_name"     { value = aws_iam_role.ec2_s3_uploader_tf.name }
output "iam_policy_name"   { value = aws_iam_policy.s3_write_envs_tf.name }
output "ec2_instance_id"   { value = aws_instance.uploader.id }
output "ec2_public_ip"     { value = aws_instance.uploader.public_ip }
