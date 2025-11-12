# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura para laboratorio de Autenticación y Autorización
# Cambios: la instancia "monitoring" ahora despliega la interfaz web del repo
# https://github.com/LucasValbuena1/PROVESI_SAS (branch: seguridad)
# ******************************************************************

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
  default     = "t3.micro"
}

provider "aws" {
  region = var.region
}

locals {
  project_name = "${var.project_prefix}-authentication"

  # Repo con TU interfaz (branch seguridad)
  repository_url   = "https://github.com/LucasValbuena1/PROVESI_SAS.git"
  repository_branch = "seguridad"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# AMI Ubuntu 24.04 LTS (Noble) oficial de Canonical
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

# SGs
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

  # Egress por defecto: all outbound permitido
  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-django" })
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

# Instancia DB (igual que antes)
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

# Instancia APP que despliega TU interfaz del branch `seguridad`
resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              set -euxo pipefail

              export DEBIAN_FRONTEND=noninteractive

              # Variable hacia DB (por si tu app la usa)
              echo "DATABASE_HOST=${aws_instance.database.private_ip}" | tee -a /etc/environment
              export DATABASE_HOST=${aws_instance.database.private_ip}

              apt-get update -y
              apt-get install -y python3-pip python3-venv git build-essential libpq-dev python3-dev
              # Nginx sólo si luego quieres servir estatico con reverse proxy; no es requerido para gunicorn/uvicorn
              # apt-get install -y nginx

              # Workspace
              APP_DIR="/opt/app"
              REPO_DIR="${APP_DIR}/PROVESI_SAS"
              mkdir -p "${APP_DIR}"
              cd "${APP_DIR}"

              if [ ! -d "${REPO_DIR}" ]; then
                git clone --branch #{BRANCH} --single-branch #{URL} "${REPO_DIR}"
              else
                cd "${REPO_DIR}"
                git fetch origin #{BRANCH}
                git checkout #{BRANCH}
                git pull --ff-only origin #{BRANCH}
              fi

              # Reemplaza placeholders
              sed -i 's|#{BRANCH}|${local.repository_branch}|g' /var/tmp/userdata-placeholder || true
              sed -i 's|#{URL}|${local.repository_url}|g' /var/tmp/userdata-placeholder || true

              cd "${REPO_DIR}"

              # Crear venv
              python3 -m venv .venv
              . .venv/bin/activate
              pip install --upgrade pip

              # Instalar requirements si existen en raiz o subcarpetas comunes
              if [ -f "requirements.txt" ]; then
                pip install -r requirements.txt
              else
                for f in app/requirements.txt src/requirements.txt web/requirements.txt backend/requirements.txt ; do
                  if [ -f "$f" ]; then pip install -r "$f"; break; fi
                done
              fi

              # Detectar tipo de app y crear servicio systemd
              SERVICE_NAME="juluapp.service"
              WORKDIR="${REPO_DIR}"
              CMD=""

              # 1) Django (manage.py)
              if [ -f "manage.py" ]; then
                CMD="/opt/app/PROVESI_SAS/.venv/bin/python3 manage.py migrate && /opt/app/PROVESI_SAS/.venv/bin/python3 manage.py runserver 0.0.0.0:8080"
              else
                # 2) Flask: app.py con "app" como WSGI
                if [ -f "app.py" ]; then
                  # Probar si es Flask
                  if grep -qi "flask" app.py; then
                    pip install gunicorn
                    CMD="/opt/app/PROVESI_SAS/.venv/bin/gunicorn app:app --bind 0.0.0.0:8080 --workers 2"
                  fi
                fi

                # 3) FastAPI/Uvicorn: main.py o app/main.py
                if [ -z "$CMD" ]; then
                  if [ -f "main.py" ] && grep -qi "fastapi" main.py; then
                    pip install uvicorn fastapi
                    CMD="/opt/app/PROVESI_SAS/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080"
                  elif [ -f "app/main.py" ] && grep -qi "fastapi" app/main.py; then
                    pip install uvicorn fastapi
                    WORKDIR="${REPO_DIR}/app"
                    CMD="/opt/app/PROVESI_SAS/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080"
                  fi
                fi
              fi

              # 4) Estático (si no hay app Python detectable): buscar un index.html
              if [ -z "$CMD" ]; then
                TARGET_STATIC="${REPO_DIR}"
                for d in . web frontend site public ; do
                  if [ -f "${REPO_DIR}/${d}/index.html" ]; then
                    TARGET_STATIC="${REPO_DIR}/${d}"
                    break
                  fi
                done
                WORKDIR="$TARGET_STATIC"
                CMD="/usr/bin/python3 -m http.server 8080"
              fi

              # Crear servicio systemd
              cat >/etc/systemd/system/${SERVICE_NAME} <<SERVICE
              [Unit]
              Description=JULU App service
              After=network.target

              [Service]
              Type=simple
              WorkingDirectory=${WORKDIR}
              Environment=PYTHONUNBUFFERED=1
              EnvironmentFile=-/etc/environment
              ExecStart=/bin/bash -lc '. ${REPO_DIR}/.venv/bin/activate && ${CMD}'
              Restart=always
              RestartSec=3

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable ${SERVICE_NAME}
              systemctl start ${SERVICE_NAME}
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-django"
    Role = "monitoring-app"
  })

  depends_on = [aws_instance.database]
}

# Outputs
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
