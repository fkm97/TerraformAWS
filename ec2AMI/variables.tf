variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env must be one of: dev, qa, prod."
  }
}

variable "app_name" {
  description = "Logical app name"
  type        = string
  default     = "webapp"
}

variable "ami_version" {
  description = "Version label baked into the AMI name; bump to create a new AMI"
  type        = string
  default     = "1.0.0"
}

variable "source_ami_id" {
  description = "Base AMI for the first instance"
  type        = string
  default     = "ami-00ca32bbc84273381" 
}

variable "instance_type_source" {
  description = "Instance type for the first (source) instance"
  type        = string
  default     = "t3.micro"
}

variable "instance_type_clone" {
  description = "Instance type for the second instance launched from the AMI"
  type        = string
  default     = "t3.micro"
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH (port 22)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Optional EC2 key pair name"
  type        = string
  default     = null
}
