variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

# You asked to keep it here (note: storing secrets in VCS is risky)
variable "db_password" {
  type        = string
  sensitive   = true
  default     = "admin123"
  description = "Postgres password"
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters."
  }
}
