terraform {
  required_providers {
    aws  = { source = "hashicorp/aws",  version = ">= 5.40" }
    time = { source = "hashicorp/time", version = ">= 0.9" }
  }
}

provider "aws" { region = var.aws_region }

# --- Network (default VPC + a subnet) ---
data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security Group: SSH in, all egress ---
resource "aws_security_group" "ssh" {
  name        = "${var.app_name}-${var.env}-ssh-sg"
  description = "SSH access for ${var.app_name}-${var.env}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
    description = "SSH"
  }

  ingress {
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "HTTP"
}

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge({ Name = "${var.app_name}-${var.env}-ssh-sg", Env = var.env }, var.extra_tags)
}

# --- 1) First EC2 instance (the source) ---
resource "aws_instance" "source" {
  ami                    = var.source_ami_id
  instance_type          = var.instance_type_source
  vpc_security_group_ids = [aws_security_group.ssh.id]
  key_name               = var.key_name

  tags = merge({
    Name = "${var.app_name}-${var.env}-source"
    App  = var.app_name
    Env  = var.env
  }, var.extra_tags)

   user_data = <<-EOF
    #!/bin/bash
    dnf -y update
    dnf -y install nginx
    systemctl enable nginx

    # Generate and persist a build id so clones inherit it
    BUILD_ID_FILE=/opt/build-id
    if [ -s "$BUILD_ID_FILE" ]; then
    BUILD_ID="$(cat "$BUILD_ID_FILE")"
    else
    BUILD_ID="$(date +%s)"
    echo -n "$BUILD_ID" > "$BUILD_ID_FILE"
    fi

    cat > /usr/share/nginx/html/index.html <<HTML
    Hello from ${var.env} AMI ${var.ami_version}
    Built from Source Build ID: $${BUILD_ID}
    HTML

    systemctl restart nginx
    EOF

}

# wait a bit so user_data finishes before snapshot
resource "time_sleep" "wait_for_setup" {
  depends_on      = [aws_instance.source]
  create_duration = "90s"
}

# --- 2) Create an AMI from the first instance ---
resource "aws_ami_from_instance" "snapshot" {
  name                    = "${var.app_name}-${var.env}-v${var.ami_version}"
  source_instance_id      = aws_instance.source.id
  snapshot_without_reboot = false

  depends_on = [time_sleep.wait_for_setup]

  tags = merge({
    Name    = "${var.app_name}-${var.env}-v${var.ami_version}"
    App     = var.app_name
    Env     = var.env
    Version = var.ami_version
  }, var.extra_tags)

  lifecycle { create_before_destroy = true }
}

# --- 3) Second EC2 instance launched from that AMI ---
resource "aws_instance" "clone" {
  ami                    = aws_ami_from_instance.snapshot.id
  instance_type          = var.instance_type_clone
  vpc_security_group_ids = [aws_security_group.ssh.id]
  key_name               = var.key_name

  tags = merge({
    Name    = "${var.app_name}-${var.env}-clone"
    App     = var.app_name
    Env     = var.env
    Version = var.ami_version
  }, var.extra_tags)

  user_data = <<-EOF
    #!/bin/bash
    dnf -y update
    dnf -y install nginx
    systemctl enable nginx

    BUILD_ID="$(cat /opt/build-id 2>/dev/null || echo UNKNOWN)"

    cat > /usr/share/nginx/html/index.html <<HTML
    CLONE - ${var.env} AMI ${var.ami_version}
    Cloned from Build ID: $${BUILD_ID}
    HTML

    systemctl restart nginx
    EOF


  # If AMI id changes (you bump ami_version), create new clone before destroying old
  lifecycle { create_before_destroy = true }

  depends_on = [aws_ami_from_instance.snapshot]
}
