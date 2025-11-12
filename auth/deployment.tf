# ---------- Variables ----------
variable "region"         { type = string, default = "us-east-1" }
variable "project_prefix" { type = string, default = "authd" }
variable "instance_type"  { type = string, default = "t2.nano" }

# Clave pública para SSH (opcional pero recomendado para entrar a las EC2)
variable "ssh_public_key" {
  type        = string
  description = "Your SSH public key content (ssh-rsa ...)"
  default     = ""
}

# ---------- Provider ----------
provider "aws" {
  region = var.region
}

# ---------- Locals ----------
locals {
  project_name = "${var.project_prefix}-authentication"
  repo_url     = "https://github.com/LucasValbuena1/PROVESI_SAS.git"
  repo_branch  = "seguridad"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# ---------- AMI Ubuntu 24.04 ----------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter { name = "name", values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] }
  filter { name = "virtualization-type", values = ["hvm"] }
}

# ---------- SSH key (opcional) ----------
resource "aws_key_pair" "this" {
  count      = length(var.ssh_public_key) > 0 ? 1 : 0
  key_name   = "${var.project_prefix}-key"
  public_key = var.ssh_public_key
}

# ---------- Security Groups ----------
resource "aws_security_group" "traffic_django" {
  name        = "${var.project_prefix}-traffic-django"
  description = "Allow app on 8080"
  ingress { from_port = 8080, to_port = 8080, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-django" })
}

resource "aws_security_group" "traffic_db" {
  name        = "${var.project_prefix}-traffic-db"
  description = "Allow PostgreSQL 5432"
  ingress { from_port = 5432, to_port = 5432, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-db" })
}

resource "aws_security_group" "traffic_ssh" {
  name        = "${var.project_prefix}-traffic-ssh"
  description = "Allow SSH 22"
  ingress { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-ssh" })
}

# ---------- DB EC2 (PostgreSQL) ----------
resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]
  key_name                    = length(var.ssh_public_key) > 0 ? aws_key_pair.this[0].key_name : null

  user_data = <<-EOT
    #!/bin/bash
    set -e
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib

    sudo -u postgres psql -c "CREATE USER monitoring_user WITH PASSWORD 'isis2503';"
    sudo -u postgres createdb -O monitoring_user monitoring_db

    echo "listen_addresses='*'" | tee -a /etc/postgresql/16/main/postgresql.conf
    echo "max_connections=2000"   | tee -a /etc/postgresql/16/main/postgresql.conf
    echo "host all all 0.0.0.0/0 trust" | tee -a /etc/postgresql/16/main/pg_hba.conf
    systemctl restart postgresql
  EOT

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-db", Role = "database" })
}

# ---------- APP EC2 (UI del repo PROVESI_SAS/seguridad) ----------
resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]
  key_name                    = length(var.ssh_public_key) > 0 ? aws_key_pair.this[0].key_name : null

  user_data = <<-EOT
    #!/bin/bash
    set -e

    # Export DB host para apps que lo necesiten
    echo "DATABASE_HOST=${aws_instance.database.private_ip}" | tee -a /etc/environment
    export DATABASE_HOST=${aws_instance.database.private_ip}

    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-venv git nginx

    # Clonar tu repo branch 'seguridad'
    mkdir -p /srv/app
    cd /srv/app
    if [ ! -d PROVESI_SAS ]; then
      git clone -b ${local.repo_branch} ${local.repo_url}
    fi
    cd PROVESI_SAS

    # Si existe requirements.txt, instalar deps en venv
    if [ -f requirements.txt ]; then
      python3 -m venv .venv
      . .venv/bin/activate
      pip install --upgrade pip
      pip install -r requirements.txt
    fi

    # Detectar Flask (app.py con Flask)
    if grep -q "Flask(" app.py 2>/dev/null; then
      # Servicio gunicorn en :8080
      cat >/etc/systemd/system/provesi.service <<'UNIT'
[Unit]
Description=Gunicorn PROVESI_SAS
After=network.target

[Service]
User=root
WorkingDirectory=/srv/app/PROVESI_SAS
Environment="DATABASE_HOST=${aws_instance.database.private_ip}"
ExecStart=/srv/app/PROVESI_SAS/.venv/bin/gunicorn -b 0.0.0.0:8080 app:app
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
      systemctl daemon-reload
      systemctl enable provesi
      systemctl start provesi

    else
      # Servir estáticos del repo con NGINX en :8080
      cat >/etc/nginx/sites-available/provesi <<'NGX'
server {
    listen 8080 default_server;
    server_name _;
    root /srv/app/PROVESI_SAS;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
NGX
      ln -sf /etc/nginx/sites-available/provesi /etc/nginx/sites-enabled/provesi
      rm -f /etc/nginx/sites-enabled/default
      systemctl restart nginx
    fi
  EOT

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-app", Role = "ui-app" })
  depends_on = [aws_instance.database]
}

# ---------- Outputs ----------
output "app_public_ip"       { value = aws_instance.app.public_ip,       description = "APP public IP (browse http://IP:8080)" }
output "db_private_ip"       { value = aws_instance.database.private_ip, description = "DB private IP" }
output "app_private_ip"      { value = aws_instance.app.private_ip,      description = "APP private IP" }
