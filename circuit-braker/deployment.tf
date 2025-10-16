# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura para laboratorio de Circuit Breaker
#
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
  default     = "t2.nano"
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

# Imagen base de Ubuntu 24.04
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

# ===================== GRUPOS DE SEGURIDAD ======================

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

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-services"
  })
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

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-cb"
  })
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

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-db"
  })
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

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-ssh"
  })
}

# ===================== INSTANCIAS ======================

# Kong
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

# PostgreSQL
resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              set -e
              sudo apt-get update -y
              sudo apt-get install -y postgresql postgresql-contrib
              sudo -u postgres psql -c "CREATE USER order_user WITH PASSWORD 'isis2503';"
              sudo -u postgres createdb -O order_user order_db
              echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
              echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
              echo "max_connections=2000" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
              sudo systemctl restart postgresql
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-db"
    Role = "database"
  })
}

# Django app (3 instancias)
resource "aws_instance" "order" {
  for_each = toset(["a", "b", "c"])

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              set -euo pipefail
              export DEBIAN_FRONTEND=noninteractive

              DATABASE_HOST="${aws_instance.database.private_ip}"
              GIT_REPO="${local.repository}"
              GIT_BRANCH="${local.branch}"
              PROJECT_DIR="/main/PROVESI_SAS"
              VENV_DIR="${PROJECT_DIR}/venv"
              SERVICE_NAME="provesi"

              apt-get update -y
              apt-get install -y python3 python3-pip python3-venv git build-essential libpq-dev python3-dev

              mkdir -p /main
              cd /main

              if [ ! -d "${PROJECT_DIR}" ]; then
                git clone "${GIT_REPO}" "${PROJECT_DIR}"
              fi

              cd "${PROJECT_DIR}"
              git fetch --all
              git checkout "${GIT_BRANCH}" || git checkout -b "${GIT_BRANCH}" "origin/${GIT_BRANCH}" || true
              git pull origin "${GIT_BRANCH}" || true

              python3 -m venv "${VENV_DIR}"
              "${VENV_DIR}/bin/pip" install --upgrade pip

              if [ -f requirements.txt ]; then
                "${VENV_DIR}/bin/pip" install -r requirements.txt || true
              fi

              "${VENV_DIR}/bin/pip" install django djangorestframework gunicorn psycopg2-binary || true

              grep -q "^DATABASE_HOST=" /etc/environment 2>/dev/null || echo "DATABASE_HOST=${DATABASE_HOST}" >> /etc/environment
              grep -q "^DJANGO_SETTINGS_MODULE=" /etc/environment 2>/dev/null || echo "DJANGO_SETTINGS_MODULE=PROVESI_SAS.settings" >> /etc/environment

              "${VENV_DIR}/bin/python" manage.py makemigrations --noinput || true
              "${VENV_DIR}/bin/python" manage.py migrate --noinput || true

              cat > /etc/systemd/system/${SERVICE_NAME}.service << SERVICE_EOF
              [Unit]
              Description=Gunicorn instance to serve PROVESI_SAS
              After=network.target

              [Service]
              Type=simple
              EnvironmentFile=/etc/environment
              WorkingDirectory=${PROJECT_DIR}
              ExecStart=${VENV_DIR}/bin/gunicorn --workers 3 --bind 0.0.0.0:8080 PROVESI_SAS.wsgi:application
              Restart=always
              RestartSec=5

              [Install]
              WantedBy=multi-user.target
              SERVICE_EOF

              systemctl daemon-reload
              systemctl enable ${SERVICE_NAME}.service
              systemctl start ${SERVICE_NAME}.service

              journalctl -u ${SERVICE_NAME}.service -n 100 --no-pager > /var/log/${SERVICE_NAME}-boot.log || true
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-order-${each.key}"
    Role = "order-app"
  })

  depends_on = [aws_instance.database]
}

# ===================== SALIDAS ======================

output "kong_public_ip" {
  description = "Public IP address for the Kong circuit breaker instance"
  value       = aws_instance.kong.public_ip
}

output "order_public_ip" {
  description = "Public IP address for the order service application"
  value       = { for id, instance in aws_instance.order : id => instance.public_ip }
}

output "order_private_ip" {
  description = "Private IP address for the order service application"
  value       = { for id, instance in aws_instance.order : id => instance.private_ip }
}

output "database_private_ip" {
  description = "Private IP address for the PostgreSQL database instance"
  value       = aws_instance.database.private_ip
}