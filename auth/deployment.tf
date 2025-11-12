############################################################
# ISIS2503 - Auth & Monitoring Stack (single-file version) #
############################################################

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "authd"
}

variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t2.nano"
}

provider "aws" {
  region = var.region
}

locals {
  project_name = "${var.project_prefix}-authentication"
  repository   = "https://github.com/ISIS2503/ISIS2503-MonitoringApp-Auth0.git"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# --- Default VPC (simple y sin complicarse)
data "aws_vpc" "default" {
  default = true
}

# AMI Ubuntu 24.04 LTS oficial de Canonical
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

# --- Security Groups ---
resource "aws_security_group" "traffic_django" {
  name        = "${var.project_prefix}-traffic-django"
  description = "Allow application traffic on port 8080"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP access for service layer"
    from_port   = 8080
    to_port     = 8080
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

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-django" })
}

resource "aws_security_group" "traffic_db" {
  name        = "${var.project_prefix}-traffic-db"
  description = "Allow PostgreSQL access (5432)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "PostgreSQL from anywhere (simplificado para el lab)"
    from_port   = 5432
    to_port     = 5432
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

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-db" })
}

resource "aws_security_group" "traffic_ssh" {
  name        = "${var.project_prefix}-traffic-ssh"
  description = "Allow SSH access (22)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH access from anywhere (simplificado para el lab)"
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

# --- EC2: PostgreSQL ---
resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              set -euxo pipefail

              apt-get update -y
              DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib

              sudo -u postgres psql -c "CREATE USER monitoring_user WITH PASSWORD 'isis2503';"
              sudo -u postgres createdb -O monitoring_user monitoring_db

              # Ajustes para permitir conexiones remotas
              echo "host all all 0.0.0.0/0 trust" >> /etc/postgresql/16/main/pg_hba.conf
              echo "listen_addresses='*'" >> /etc/postgresql/16/main/postgresql.conf
              echo "max_connections=2000" >> /etc/postgresql/16/main/postgresql.conf

              systemctl restart postgresql
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-db"
    Role = "database"
  })
}

# --- EC2: Monitoring (Django) ---
resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              set -euxo pipefail

              export DATABASE_HOST=${aws_instance.database.private_ip}
              echo "DATABASE_HOST=${aws_instance.database.private_ip}" >> /etc/environment

              apt-get update -y
              DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-venv git build-essential libpq-dev python3-dev

              mkdir -p /labs
              cd /labs

              if [ ! -d ISIS2503-MonitoringApp-Auth0 ]; then
                git clone ${local.repository}
              fi

              cd ISIS2503-MonitoringApp-Auth0

              pip3 install --upgrade pip --break-system-packages
              pip3 install -r requirements.txt --break-system-packages

              # Migraciones
              DATABASE_HOST=${aws_instance.database.private_ip} python3 manage.py makemigrations
              DATABASE_HOST=${aws_instance.database.private_ip} python3 manage.py migrate

              # Correr el servidor de desarrollo en :8080
              nohup bash -c 'DATABASE_HOST=${aws_instance.database.private_ip} python3 manage.py runserver 0.0.0.0:8080' >/var/log/monitoring_app.log 2>&1 &
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-django"
    Role = "monitoring-app"
  })

  depends_on = [aws_instance.database]
}

# --- Outputs ---
output "monitoring_public_ip" {
  description = "Public IP address for the monitoring service application"
  value       = aws_instance.monitoring.public_ip
}

output "monitoring_private_ip" {
  description = "Private IP address for the monitoring service application"
  value       = aws_instance.monitoring.private_ip
}

output "database_private_ip" {
  description = "Private IP address for the PostgreSQL database instance"
  value       = aws_instance.database.private_ip
}
