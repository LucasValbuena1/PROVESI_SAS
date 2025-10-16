# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura para laboratorio de Circuit Breaker
#
# Elementos a desplegar en AWS:
# 1. Grupos de seguridad:
#    - cbd-traffic-django (puerto 8080)
#    - cbd-traffic-cb (puertos 8000 y 8001)
#    - cbd-traffic-db (puerto 5432)
#    - cbd-traffic-ssh (puerto 22)
#
# 2. Instancias EC2:
#    - cbd-kong
#    - cbd-db (PostgreSQL instalado y configurado)
#    - cbd-order-a, cbd-order-b, cbd-order-c (App Django instalada)
# ******************************************************************

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "cbd"
}

variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t2.micro"
}

provider "aws" {
  region = var.region
}

locals {
  project_name = "${var.project_prefix}"
  repository   = "https://github.com/LucasValbuena1/PROVESI_SAS.git"
  branch       = "Circuit-Breaker"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# -------------------- Imagen base --------------------
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

# -------------------- Seguridad --------------------

resource "aws_security_group" "traffic_django" {
  name        = "${var.project_prefix}-traffic-django"
  description = "Allow application traffic on port 8080"

  ingress {
    description = "HTTP access for service layer"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-services" })
}

resource "aws_security_group" "traffic_cb" {
  name        = "${var.project_prefix}-traffic-cb"
  description = "Expose Kong ports"

  ingress {
    description = "Kong traffic"
    from_port   = 8000
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-cb" })
}

resource "aws_security_group" "traffic_db" {
  name        = "${var.project_prefix}-traffic-db"
  description = "Allow PostgreSQL access"

  ingress {
    description = "Traffic from anywhere to DB"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-db" })
}

resource "aws_security_group" "traffic_ssh" {
  name        = "${var.project_prefix}-traffic-ssh"
  description = "Allow SSH access"

  ingress {
    description = "SSH access from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-ssh" })
}

# -------------------- Kong --------------------
resource "aws_instance" "kong" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_cb.id, aws_security_group.traffic_ssh.id]

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-kong"
    Role = "circuit-breaker"
  })
}

# -------------------- Base de datos PostgreSQL --------------------
resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              apt-get update -y
              apt-get install -y postgresql postgresql-contrib
              sudo -u postgres psql -c "CREATE USER order_user WITH PASSWORD 'isis2503';"
              sudo -u postgres createdb -O order_user order_db
              echo "host all all 0.0.0.0/0 trust" | tee -a /etc/postgresql/16/main/pg_hba.conf
              echo "listen_addresses='*'" | tee -a /etc/postgresql/16/main/postgresql.conf
              echo "max_connections=2000" | tee -a /etc/postgresql/16/main/postgresql.conf
              systemctl restart postgresql
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-db"
    Role = "database"
  })
}

# -------------------- App Django (3 instancias) --------------------
resource "aws_instance" "order" {
  for_each = t_