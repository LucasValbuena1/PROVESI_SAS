############################################################
# PROVESI_SAS - Auth & Monitoring Stack (parametrizado)   #
############################################################

variable "region"         { type = string  default = "us-east-1" }
variable "project_prefix" { type = string  default = "authd" }
variable "instance_type"  { type = string  default = "t2.nano" }

# === REPO Y APP (AJUSTA SI TU CÓDIGO ESTÁ EN OTRA RUTA) ===
variable "repository_url" { type = string  default = "https://github.com/LucasValbuena1/PROVESI_SAS.git" }
variable "repository_branch" { type = string default = "Deployments" }     # ej: main, Deployments, etc.
variable "app_subdir"        { type = string default = "" }                # ej: "apps/monitoring" si la app no está en raíz
variable "app_start_cmd"     { type = string default = "python3 manage.py runserver 0.0.0.0:8080" }

# === DB (CREDENCIALES DE LAB) ===
variable "db_name"     { type = string default = "monitoring_db" }
variable "db_user"     { type = string default = "monitoring_user" }
variable "db_password" { type = string default = "isis2503" }

provider "aws" { region = var.region }

locals {
  project_name = "${var.project_prefix}-authentication"
  common_tags = { Project = local.project_name, ManagedBy = "Terraform" }
}

data "aws_vpc" "default" { default = true }

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter { name = "name"  values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] }
  filter { name = "virtualization-type" values = ["hvm"] }
}

# --- Security Groups ---
resource "aws_security_group" "traffic_django" {
  name        = "${var.project_prefix}-traffic-django"
  description = "Allow app traffic 8080"
  vpc_id      = data.aws_vpc.default.id
  ingress { from_port = 8080 to_port = 8080 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-django" })
}

resource "aws_security_group" "traffic_db" {
  name        = "${var.project_prefix}-traffic-db"
  description = "Allow PostgreSQL 5432"
  vpc_id      = data.aws_vpc.default.id
  ingress { from_port = 5432 to_port = 5432 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-db" })
}

resource "aws_security_group" "traffic_ssh" {
  name        = "${var.project_prefix}-traffic-ssh"
  description = "Allow SSH 22"
  vpc_id      = data.aws_vpc.default.id
  ingress { from_port = 22 to_port = 22 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
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
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y postgresql postgresql-contrib

    sudo -u postgres psql -c "CREATE USER ${var.db_user} WITH PASSWORD '${var.db_password}';"
    sudo -u postgres createdb -O ${var.db_user} ${var.db_name}

    echo "host all all 0.0.0.0/0 trust" >> /etc/postgresql/16/main/pg_hba.conf
    echo "listen_addresses='*'"         >> /etc/postgresql/16/main/postgresql.conf
    echo "max_connections=2000"         >> /etc/postgresql/16/main/postgresql.conf
    systemctl restart postgresql
  EOT

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-db", Role = "database" })
}

# --- EC2: App (Django u otra) desde TU repo ---
resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive

    # Vars derivadas
    DB_HOST="${aws_instance.database.private_ip}"
    REPO_URL="${var.repository_url}"
    REPO_BRANCH="${var.repository_branch}"
    APP_SUBDIR="${var.app_subdir}"

    # Dependencias base
    apt-get update -y
    apt-get install -y python3-pip python3-venv git build-essential libpq-dev python3-dev

    # Workspace
    mkdir -p /labs && cd /labs
    if [ ! -d repo ]; then
      git clone -b "$REPO_BRANCH" "$REPO_URL" repo
    fi

    cd repo
    if [ -n "$APP_SUBDIR" ]; then
      cd "$APP_SUBDIR"
    fi

    # Python deps
    pip3 install --upgrade pip --break-system-packages || true
    if [ -f requirements.txt ]; then
      pip3 install -r requirements.txt --break-system-packages || true
    fi

    # Export DB envs coherentes con tu app (ajústalos si tu app usa otros nombres)
    echo "DATABASE_HOST=$DB_HOST" >> /etc/environment
    echo "DATABASE_NAME=${var.db_name}" >> /etc/environment
    echo "DATABASE_USER=${var.db_user}" >> /etc/environment
    echo "DATABASE_PASSWORD=${var.db_password}" >> /etc/environment

    # Migraciones si es Django (ignora errores si no es Django)
    ( DATABASE_HOST=$DB_HOST DATABASE_NAME=${var.db_name} DATABASE_USER=${var.db_user} DATABASE_PASSWORD='${var.db_password}' \
      python3 manage.py makemigrations || true )
    ( DATABASE_HOST=$DB_HOST DATABASE_NAME=${var.db_name} DATABASE_USER=${var.db_user} DATABASE_PASSWORD='${var.db_password}' \
      python3 manage.py migrate || true )

    # Arranque (parametrizado)
    nohup bash -c '${var.app_start_cmd}' > /var/log/app.log 2>&1 &
  EOT

  depends_on = [aws_instance.database]

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-app", Role = "application" })
}

# --- Outputs ---
output "app_public_ip"     { value = aws_instance.app.public_ip     description = "Public IP of the app host" }
output "app_private_ip"    { value = aws_instance.app.private_ip    description = "Private IP of the app host" }
output "database_private_ip" { value = aws_instance.database.private_ip description = "Private IP of DB" }
