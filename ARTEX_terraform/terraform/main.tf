terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-west-2"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR notation, e.g. 203.0.113.10/32"
}

variable "key_name" {
  description = "Existing EC2 key-pair name"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


data "aws_availability_zones" "available" {}

resource "aws_vpc" "artex" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "artex-vpc"
  }
}

resource "aws_subnet" "artex_public" {
  vpc_id                  = aws_vpc.artex.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "artex-public-subnet"
  }
}

resource "aws_internet_gateway" "artex" {
  vpc_id = aws_vpc.artex.id
}

resource "aws_route_table" "artex_public" {
  vpc_id = aws_vpc.artex.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.artex.id
  }
}

resource "aws_route_table_association" "artex_public" {
  subnet_id      = aws_subnet.artex_public.id
  route_table_id = aws_route_table.artex_public.id
}


resource "aws_security_group" "artex" {
  name        = "artex-sandbox"
  description = "Private ARTEX sandbox"
  vpc_id      = aws_vpc.artex.id

  ingress {
    description = "SSH from administrator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "artex" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.large"
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.artex_public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.artex.id]

  root_block_device {
    volume_size = 80
    volume_type = "gp3"
  }

  user_data = <<-EOF
  #!/bin/bash
  set -euxo pipefail

  exec > >(tee /var/log/artex-user-data.log | logger -t artex-user-data -s 2>/dev/console) 2>&1

  apt-get update
  apt-get install -y ca-certificates curl git

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
  usermod -aG docker ubuntu

  git clone https://github.com/dougc333/ARTEX.git /opt/ARTEX
  cd /opt/ARTEX

  cp .env.example .env
  printf "\nPOSTGRES_PASSWORD=%s\n" "$(openssl rand -hex 24)" >> .env

  docker compose up -d --build
EOF

  tags = {
    Name = "artex-sandbox"
  }
}

output "instance_public_ip" {
  value = aws_instance.artex.public_ip
}
