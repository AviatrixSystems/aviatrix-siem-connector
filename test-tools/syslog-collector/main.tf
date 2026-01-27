provider "aws" {
  region = var.aws_region
}

# Random string for unique resource naming
resource "random_string" "random" {
  length  = 8
  special = false
  upper   = false
}

# VPC and networking
resource "aws_vpc" "syslog_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "syslog-collector-vpc-${random_string.random.id}"
  })
}

resource "aws_internet_gateway" "syslog_igw" {
  vpc_id = aws_vpc.syslog_vpc.id

  tags = merge(var.tags, {
    Name = "syslog-collector-igw-${random_string.random.id}"
  })
}

resource "aws_subnet" "syslog_public_subnet" {
  vpc_id                  = aws_vpc.syslog_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "syslog-collector-public-subnet-${random_string.random.id}"
  })
}

resource "aws_route_table" "syslog_public_rt" {
  vpc_id = aws_vpc.syslog_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.syslog_igw.id
  }

  tags = merge(var.tags, {
    Name = "syslog-collector-public-rt-${random_string.random.id}"
  })
}

resource "aws_route_table_association" "syslog_public_rta" {
  subnet_id      = aws_subnet.syslog_public_subnet.id
  route_table_id = aws_route_table.syslog_public_rt.id
}

# Security Group
resource "aws_security_group" "syslog_collector_sg" {
  name_prefix = "syslog-collector-sg-${random_string.random.id}"
  vpc_id      = aws_vpc.syslog_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # Syslog UDP
  ingress {
    from_port   = 514
    to_port     = 514
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Syslog TCP
  ingress {
    from_port   = 514
    to_port     = 514
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Web UI
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.web_ui_allowed_cidrs
  }

  # HTTPS (for future use)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.web_ui_allowed_cidrs
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "syslog-collector-sg-${random_string.random.id}"
  })
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance
resource "aws_instance" "syslog_collector" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.ssh_key_name
  vpc_security_group_ids      = [aws_security_group.syslog_collector_sg.id]
  subnet_id                   = aws_subnet.syslog_public_subnet.id
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh", {
    web_ui_password = var.web_ui_password
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "syslog-collector-${random_string.random.id}"
  })
}

# Elastic IP
resource "aws_eip" "syslog_collector_eip" {
  domain   = "vpc"
  instance = aws_instance.syslog_collector.id

  tags = merge(var.tags, {
    Name = "syslog-collector-eip-${random_string.random.id}"
  })

  depends_on = [aws_internet_gateway.syslog_igw]
}
