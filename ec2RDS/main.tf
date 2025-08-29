terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.40" }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------- AZs & simple names ----------------
data "aws_availability_zones" "azs" { state = "available" }

locals {
  az1 = data.aws_availability_zones.azs.names[0]
  az2 = data.aws_availability_zones.azs.names[1]
}

# ---------------- VPC & Subnets ----------------
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "demo-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "demo-igw" }
}

# Public subnet (EC2 + Internet)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags = { Name = "public-a" }
}

# Private subnets (RDS must span 2 AZs)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = local.az1
  tags = { Name = "private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = local.az2
  tags = { Name = "private-b" }
}

# Public route to Internet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route { 
  cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id 
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# Private route table (no Internet route)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ---------------- Security Groups ----------------
# EC2: allow HTTP in from anywhere, all egress
resource "aws_security_group" "ec2_sg" {
  name   = "ec2-http"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ec2-http" }
}

# RDS SG (no inline ingress here)
resource "aws_security_group" "rds_sg" {
  name   = "rds-postgres"
  vpc_id = aws_vpc.vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

# Allow Postgres to RDS from the EC2 SG
resource "aws_security_group_rule" "rds_from_ec2" {
  type                     = "ingress"
  description              = "Postgres from EC2"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_sg.id          # target SG (RDS)
  source_security_group_id = aws_security_group.ec2_sg.id           # source SG (EC2)
}

# ---------------- RDS (PostgreSQL) ----------------
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "rds-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = { Name = "rds-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier             = "demo-postgres"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20

  username = var.db_username
  password = var.db_password
  db_name  = var.db_name

  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible = false
  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true

  tags = { Name = "demo-postgres" }
}

# ---------------- EC2 (public) + Nginx ----------------
resource "aws_instance" "web" {
  ami                         = "ami-00ca32bbc84273381" 
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf -y install nginx
    systemctl enable nginx
    cat > /usr/share/nginx/html/index.html <<HTML
    <h1>EC2 + Nginx</h1>
    <p>RDS endpoint: ${aws_db_instance.postgres.address}</p>
    <p>DB name: ${var.db_name}</p>
    HTML
    systemctl restart nginx
  EOF

  tags = { Name = "web-public" }

  depends_on = [aws_db_instance.postgres]
}
