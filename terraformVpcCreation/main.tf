terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.40" }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ---------------- VPC ----------------
resource "aws_vpc" "vpc" {
  cidr_block           = "192.0.0.0/16"   
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "custom-made-vpc" }
}

# ---------------- Subnets ----------------
locals {
  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Pick any clean split; /24 gives room
  public_cidrs  = ["192.0.1.0/24",  "192.0.2.0/24", "192.0.3.0/24"]
  private_cidrs = ["192.0.4.0/24", "192.0.5.0/24", "192.0.6.0/24"]
}

# Public subnets
resource "aws_subnet" "public1a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = local.public_cidrs[0]
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true
  tags = { Name = "custom-made-subnet-public1-us-east-1a" }
}
resource "aws_subnet" "public1b" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = local.public_cidrs[1]
  availability_zone       = local.azs[1]
  map_public_ip_on_launch = true
  tags = { Name = "custom-made-subnet-public2-us-east-1b" }
}
resource "aws_subnet" "public1c" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = local.public_cidrs[2]
  availability_zone       = local.azs[2]
  map_public_ip_on_launch = true
  tags = { Name = "custom-made-subnet-public3-us-east-1c" }
}

# Private subnets
resource "aws_subnet" "private1a" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.private_cidrs[0]
  availability_zone = local.azs[0]
  tags = { Name = "custom-made-subnet-private1-us-east-1a" }
}
resource "aws_subnet" "private1b" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.private_cidrs[1]
  availability_zone = local.azs[1]
  tags = { Name = "custom-made-subnet-private2-us-east-1b" }
}
resource "aws_subnet" "private1c" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.private_cidrs[2]
  availability_zone = local.azs[2]
  tags = { Name = "custom-made-subnet-private3-us-east-1c" }
}

# ---------------- IGW + NAT ----------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "custom-made-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "custom-made-nat-eip" }
}

# NAT in public subnet (us-east-1a)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public1a.id
  tags          = { Name = "custom-made-nat-public1-us-east-1a" }

  depends_on = [aws_internet_gateway.igw]
}

# ---------------- Route tables ----------------
# Public RT: 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "custom-made-rtb-public" }
}
resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
# Associate public subnets
resource "aws_route_table_association" "public1a" {
  subnet_id      = aws_subnet.public1a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public1b" {
  subnet_id      = aws_subnet.public1b.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public1c" {
  subnet_id      = aws_subnet.public1c.id
  route_table_id = aws_route_table.public.id
}

# Private RT (1a): 0.0.0.0/0 -> NAT
resource "aws_route_table" "private1a" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "custom-made-rtb-private1-us-east-1a" }
}
resource "aws_route" "private1a_default" {
  route_table_id         = aws_route_table.private1a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}
resource "aws_route_table_association" "private1a" {
  subnet_id      = aws_subnet.private1a.id
  route_table_id = aws_route_table.private1a.id
}

# Private RT (1b)
resource "aws_route_table" "private1b" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "custom-made-rtb-private2-us-east-1b" }
}
resource "aws_route" "private1b_default" {
  route_table_id         = aws_route_table.private1b.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}
resource "aws_route_table_association" "private1b" {
  subnet_id      = aws_subnet.private1b.id
  route_table_id = aws_route_table.private1b.id
}

# Private RT (1c)
resource "aws_route_table" "private1c" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "custom-made-rtb-private3-us-east-1c" }
}
resource "aws_route" "private1c_default" {
  route_table_id         = aws_route_table.private1c.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}
resource "aws_route_table_association" "private1c" {
  subnet_id      = aws_subnet.private1c.id
  route_table_id = aws_route_table.private1c.id
}

# ---------------- Outputs ----------------
output "vpc_id"               { value = aws_vpc.vpc.id }
output "public_subnet_ids"    { value = [aws_subnet.public1a.id, aws_subnet.public1b.id, aws_subnet.public1c.id] }
output "private_subnet_ids"   { value = [aws_subnet.private1a.id, aws_subnet.private1b.id, aws_subnet.private1c.id] }
output "igw_id"               { value = aws_internet_gateway.igw.id }
output "nat_gateway_id"       { value = aws_nat_gateway.nat.id }
output "public_route_table"   { value = aws_route_table.public.id }
output "private_route_tables" { value = [aws_route_table.private1a.id, aws_route_table.private1b.id, aws_route_table.private1c.id] }
