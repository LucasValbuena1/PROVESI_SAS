# Variable. Define la región de AWS donde se desplegará la infraestructura.
  variable "region" {
    description = "AWS region for deployment"
    type        = string
    default     = "us-east-1"
  }

  # Variable. Define el prefijo usado para nombrar los recursos en AWS.
  variable "project_prefix" {
    description = "Prefix used for naming AWS resources"
    type        = string
    default     = "wms"
  }

  # Variable. Define el tipo de instancia EC2 a usar para las máquinas virtuales.
  variable "instance_type" {
    description = "EC2 instance type for application hosts"
    type        = string
    default     = "t2.nano"
  }

  # Proveedor. Define el proveedor de infraestructura (AWS) y la región.
  provider "aws" {
    region = var.region
  }

  # Variables locales usadas en la configuración de Terraform.
  locals {
    project_name = "${var.project_prefix}"
    repository   = "https://github.com/LucasValbuena1/PROVESI_SAS.git"
    branch       = "Circuit-Breaker"

    common_tags = {
      Project   = local.project_name
      ManagedBy = "Terraform"
    }
  }

  # Data Source. Busca la AMI más reciente de Ubuntu 24.04 usando los filtros especificados.
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

  # Recurso. Define el grupo de seguridad para el tráfico de Django (8080).
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

  # Recurso. Define el grupo de seguridad para el tráfico del Circuit Breaker (8000, 8001).
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

  # Recurso. Define el grupo de seguridad para el tráfico de la base de datos (5432).
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

  # Recurso. Define el grupo de seguridad para el tráfico SSH (22) y permite todo el tráfico saliente.
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

  # Recurso. Define la instancia EC2 para Kong (Circuit Breaker).
  # Esta instancia se crea planamente sin configuración adicional.
  resource "aws_instance" "kong" {
    ami                         = data.aws_ami.ubuntu.id
    instance_type               = var.instance_type
    associate_public_ip_address = true
    vpc_security_group_ids      = [aws_security_group.traffic_cb.id, aws_security_group.traffic_ssh.id]

    tags = merge(local.common_tags, {
      Name = "${var.project_prefix}-kong"
      Role = "circuit-Breaker"
    })
  }

  # Recurso. Define la instancia EC2 para la base de datos PostgreSQL.
  # Esta instancia incluye un script de creación para instalar y configurar PostgreSQL.
  # El script crea un usuario y una base de datos, y ajusta la configuración para permitir conexiones remotas.
  resource "aws_instance" "database" {
    ami                         = data.aws_ami.ubuntu.id
    instance_type               = var.instance_type
    associate_public_ip_address = false
    vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]

    user_data = <<-EOT
                #!/bin/bash

                sudo apt-get update -y
                sudo apt-get install -y postgresql-15 postgresql-contrib-15

                sudo -u postgres psql -c "CREATE USER inventario_user WITH PASSWORD 'isis2503';"
                sudo -u postgres createdb -O inventario_user inventario_db
                echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/15/main/pg_hba.conf
                echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/15/main/postgresql.conf
                echo "max_connections=2000" | sudo tee -a /etc/postgresql/15/main/postgresql.conf
                sudo service postgresql restart
                EOT

    tags = merge(local.common_tags, {
      Name = "${var.project_prefix}-db"
      Role = "database"
    })
  }


  # Recurso. Define la instancia EC2 para la aplicación de Monitoring (Django).
  # Esta instancia incluye un script de creación para instalar la aplicación de Monitoring y aplicar las migraciones.
  resource "aws_instance" "inventario" {
    for_each = toset(["a"])

    ami                         = data.aws_ami.ubuntu.id
    instance_type               = var.instance_type
    associate_public_ip_address = true
    vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]

user_data = <<-EOT
              #!/bin/bash
              set -e  # detener el script si algo falla

              # ==== Variables de entorno ====
              export DEBIAN_FRONTEND=noninteractive
              export DATABASE_HOST=${aws_instance.database.private_ip}
              echo "DATABASE_HOST=${aws_instance.database.private_ip}" | sudo tee -a /etc/environment

              # ==== Instalación de dependencias ====
              sudo apt-get update -y
              sudo apt-get install -y python3 python3-pip python3-venv git build-essential libpq-dev python3-dev

              # ==== Preparar directorio ====
              mkdir -p /main
              cd /main

              # ==== Clonar repositorio ====
              if [ ! -d PROVESI_SAS ]; then
                git clone ${local.repository} PROVESI_SAS
              fi

              cd PROVESI_SAS
              git fetch origin ${local.branch}
              git checkout ${local.branch}

              # ==== Crear entorno virtual ====
              python3 -m venv venv
              source venv/bin/activate

              # ==== Instalar dependencias manualmente (sin requirements.txt) ====
              pip install --upgrade --break-system-packages pip
              pip install --break-system-packages django djangorestframework psycopg2-binary gunicorn

              # ==== Migraciones ====
              python manage.py makemigrations
              python manage.py migrate

              # ==== Iniciar servidor (opcional) ====
              nohup python manage.py runserver 0.0.0.0:8080 &
            EOT


    tags = merge(local.common_tags, {
      Name = "${var.project_prefix}-inventario-${each.key}"
      Role = "inventario-app"
    })

    depends_on = [aws_instance.database]
  }

  # Salida. Muestra la dirección IP pública de la instancia de Kong (Circuit Breaker).
  output "kong_public_ip" {
    description = "Public IP address for the Kong circuit breaker instance"
    value       = aws_instance.kong.public_ip
  }

  # Salida. Muestra la dirección IP pública de la instancia de la aplicación de Monitoring.
  output "inventario_public_ip" {
    description = "Public IP address for the inventario service application"
    value       = { for id, instance in aws_instance.inventario : id => instance.private_ip }
  }

  # Salida. Muestra la dirección IP privada de la instancia de la aplicación de Monitoring.
  output "inventario_private_ip" {
    description = "Private IP address for the inventario service application"
    value       = {for id, instance in aws_instance.inventario : id => instance.private_ip }
  }

  # Salida. Muestra la dirección IP privada de la instancia de la base de datos PostgreSQL.
  output "database_private_ip" {
    description = "Private IP address for the PostgreSQL database instance"
    value       = aws_instance.database.private_ip
}

