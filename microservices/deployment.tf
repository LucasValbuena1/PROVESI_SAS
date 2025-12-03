# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura para el Sprint 4 - Grupo 1 Alphacommit
#
# Elementos a desplegar en AWS:
# 1. Grupos de seguridad:
#    - msd-traffic-api (puerto 8080)
#    - msd-traffic-apps (puerto 8080)
#    - msd-traffic-db-postgres (puerto 5432)
#    - msd-traffic-db-mongo  (puerto 27017)
#    - cbd-traffic-ssh (puerto 22)
#
# 2. Instancias EC2:
#    - msd-clients-db (MongoDB instalado y configurado)
#    - msd-orders-db (PostgreSQL instalado y configurado)
#    - msd-clients-ms (Servicio de variables descargado)
#    - msd-orders-ms (Servicio de measurements instalado y configurado)
#    - msd-kong (Kong API Gateway instalado y configurado)
# ******************************************************************

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.18.0"
    }
  }
}

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
  default     = "msd"
}

# Variable. Define el tipo de instancia EC2 a usar para las máquinas virtuales.
variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t3.micro"
}

# Proveedor. Define el proveedor de infraestructura (AWS) y la región.
provider "aws" {
  region = var.region
}

# Variables locales usadas en la configuración de Terraform.
locals {
  project_name = "${var.project_prefix}-microservices"
  repository   = "https://github.com/LucasValbuena1/PROVESI_SAS.git"

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

# Recurso. Define el grupo de seguridad para el tráfico del API gateway (8000).
resource "aws_security_group" "traffic_api" {
    name        = "${var.project_prefix}-traffic-api"
    description = "Allow application traffic on port 8000"

    ingress {
        description = "HTTP access for gateway layer"
        from_port   = 8000
        to_port     = 8000
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = merge(local.common_tags, {
        Name = "${var.project_prefix}-traffic-api"
    })
}

# Recurso. Define el grupo de seguridad para el tráfico de los microservicios (8080).
resource "aws_security_group" "traffic_apps" {
    name        = "${var.project_prefix}-traffic-apps"
    description = "Allow application traffic on port 8080"

    ingress {
        description = "HTTP access for service layer"
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = merge(local.common_tags, {
        Name = "${var.project_prefix}-traffic-apps"
    })
}

# Recurso. Define el grupo de seguridad para el tráfico de las bases de datos (5432).
resource "aws_security_group" "traffic_db_postgres" {
  name        = "${var.project_prefix}-traffic-db-postgres"
  description = "Allow PostgreSQL access"

  ingress {
    description = "Traffic from anywhere to DB"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-db-postgres"
  })
}

# Recurso. Define el grupo de seguridad para el tráfico de la base de datos MongoDB (27017).
resource "aws_security_group" "traffic_db_mongo" {
  name        = "${var.project_prefix}-traffic-mongo"
  description = "Allow MongoDB access"

  ingress {
    description = "Traffic from anywhere to DB"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-db-mongo"
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

# Recurso. Define la instancia EC2 para la base de datos PostgreSQL de órdenes.
# Esta instancia incluye un script de creación para instalar y configurar PostgreSQL.
# El script crea un usuario y una base de datos, y ajusta la configuración para permitir conexiones remotas.
resource "aws_instance" "orders_db" {
  ami                         = "ami-051685736c7b35f95"
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_db_postgres.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              set -euxo pipefail

              export DEBIAN_FRONTEND=noninteractive
              apt-get update -y
              apt-get install -y postgresql postgresql-contrib

              sudo -u postgres psql -c "CREATE USER provesi WITH PASSWORD '1234';"
              sudo -u postgres createdb -O provesi provesi_wms
              sudo -u postgres createdb -O provesi provesi_orders
              echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
              echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
              echo "max_connections=2000" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
              sudo service postgresql restart
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-orders-db"
    Role = "orders-db"
  })
}
#TODO: Revisar como es la config de Mongo
# Recurso. Define la instancia EC2 para la base de datos MongoDB de clientes (clients).
# Esta instancia incluye un script de creación para instalar y configurar MongoDB.
resource "aws_instance" "clients_db" {
  ami                         = "ami-051685736c7b35f95"
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_db_mongo.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash

              docker run --restart=always -d -e POSTGRES_USER=measurements_user -e POSTGRES_DB=measurements_db -e POSTGRES_PASSWORD=isis2503 -p 5432:5432 --name measurements-db postgres
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-clients-db"
    Role = "clients-db"
  })
}

# Recurso. Define la instancia EC2 para el microservicio de clients (Fast API).
# Esta instancia incluye un script de creación para instalar el microservicio de Clientes y aplicar las migraciones.
resource "aws_instance" "clients_ms" {
  ami                         = "ami-051685736c7b35f95"
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_apps.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              
              sudo export PLACES_DB_HOST=${aws_instance.clients_db.private_ip}
              echo "PLACES_DB_HOST=${aws_instance.clients_db.private_ip}" | sudo tee -a /etc/environment

              sudo apt-get update -y
              sudo apt-get install -y python3-pip git build-essential libpq-dev python3-dev

              mkdir -p /labs
              cd /labs

              if [ ! -d PROVESI_SAS ]; then
                git clone ${local.repository}
              fi
              
              cd PROVESI_SAS

              sudo apt install -y python3.12-venv
              sudo python3 -m venv venv
              sudo venv/bin/pip install -r requirements.txt
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-clients-ms"
    Role = "clients-ms"
  })

  depends_on = [aws_instance.clients_db]
}

# Recurso. Define la instancia EC2 para el microservicio de orders (Fast API).
# Esta instancia incluye un script de creación para instalar el microservicio de órdenes y aplicar las migraciones.
resource "aws_instance" "orders_ms" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_apps.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash

              sudo export PLACES_DB_HOST=${aws_instance.orders_db.private_ip}
              echo "PLACES_DB_HOST=${aws_instance.orders_db.private_ip}" | sudo tee -a /etc/environment

              sudo apt-get update -y
              sudo apt-get install -y python3-pip git build-essential libpq-dev python3-dev

              mkdir -p /labs
              cd /labs

              if [ ! -d PROVESI_SAS ]; then
                git clone ${local.repository}
              fi
              
              cd PROVESI_SAS

              sudo apt install -y python3.12-venv
              sudo python3 -m venv venv
              sudo venv/bin/pip install -r requirements.txt
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-orders-ms"
    Role = "orders-ms"
  })

  depends_on = [aws_instance.orders_db]
}
#TODO: Revisar la parte que tiene lo de Docker
# Recurso. Define la instancia EC2 para Kong (API Gateway).
resource "aws_instance" "kong" {
  ami                         = "ami-051685736c7b35f95"
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_api.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash

              sudo export CLIENTS_HOST=${aws_instance.clients_ms.private_ip}
              echo "CLIENTS_HOST=${aws_instance.clients_ms.private_ip}" | sudo tee -a /etc/environment
              sudo export ORDERS_HOST=${aws_instance.orders_ms.private_ip}
              echo "ORDERS_HOST=${aws_instance.orders_ms.private_ip}" | sudo tee -a /etc/environment


              sudo dnf install nano git -y
              sudo mkdir /labs
              cd /labs
              sudo git clone https://github.com/LucasValbuena1/PROVESI_SAS.git
              cd PROVESI_SAS

              # Configurar el archivo kong.yaml con las IPs de los microservicios

              sudo sed -i "s/<CLIENTS_HOST>/${aws_instance.variables_ms.private_ip}/g" kong.yaml
              sudo sed -i "s/<ORDERS_HOST>/${aws_instance.measurements_ms.private_ip}/g" kong.yaml
              docker network create kong-net
              docker run -d --name kong --network=kong-net --restart=always \
              -v "$(pwd):/kong/declarative/" -e "KONG_DATABASE=off" \
              -e "KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yaml" \
              -p 8000:8000 kong/kong-gateway
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-kong"
    Role = "api-gateway"
  })

  depends_on = [aws_instance.variables_ms, aws_instance.measurements_ms]
}

# Salida. Muestra la dirección IP pública de la instancia de Kong (API Gateway).
output "kong_public_ip" {
  description = "Public IP address for the Kong API Gateway instance"
  value       = aws_instance.kong.public_ip
}

# Salida. Muestra las direcciones IP públicas de la instancia de Clients MS.
output "clients_ms_public_ip" {
  description = "Public IP address for the Clients Microservice instance"
  value       = aws_instance.clients_ms.public_ip
}

# Salida. Muestra las direcciones IP públicas de la instancia de Orders MS.
output "orders_ms_public_ip" {
  description = "Public IP address for the Orders Microservice instance"
  value       = aws_instance.orders_ms.public_ip
}

# Salida. Muestra las direcciones IP privadas de la instancia de la base de datos de Clients.
output "clients_db_private_ip" {
  description = "Private IP address for the Cients Database instance"
  value       = aws_instance.clients_db.private_ip
}

# Salida. Muestra las direcciones IP privadas de la instancia de la base de datos de Orders.
output "orders_db_private_ip" {   
  description = "Private IP address for the orders Database instance"
  value       = aws_instance.orders_db.private_ip
}