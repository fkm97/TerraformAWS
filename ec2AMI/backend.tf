terraform {
  backend "s3" {
    bucket         = "assignmentbucket20250828"
    key            = "ami-demo/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "test-iac"
    encrypt        = true
  }
}
