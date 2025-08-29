terraform {
  backend "s3" {
    bucket         = "assignmentbucket20250829"
    key            = "VPC/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "test-iac"
    encrypt        = true
  }
}
