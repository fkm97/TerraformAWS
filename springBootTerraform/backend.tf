terraform {
  backend "s3" {
    bucket         = "assignmentbucket20250901"
    key            = "springBootTerraform/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "test-iac"
    encrypt        = true
  }
}
