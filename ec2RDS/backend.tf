terraform {
  backend "s3" {
    bucket         = "assignmentbucket20250829"
    key            = "ec2-rds-demo/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "test-iac"
    encrypt        = true
  }
}
