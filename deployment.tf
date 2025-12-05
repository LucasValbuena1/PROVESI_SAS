# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura PROVESI WMS - Sistema de Gestión de Almacén
#
# Arquitectura:
# - 1 Instancia EC2 para PostgreSQL (provesi_orders)
# - 1 Instancia EC2 para MongoDB (provesi_clients)
# - 1 Instancia EC2 para la Aplicación (Django + FastAPI)
#
# La aplicación corre en el puerto 8000 con Uvicorn
# ******************************************************************

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

# ==================== VARIABLES ====================

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "provesi"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "db_instance_type" {
  description = "EC2 instance type for databases"
  type        = string
  default     = "t3.micro"
}

# ==================== PROVIDER ====================

provider "aws" {
  region = var.region
}

# ==================== LOCALS ====================

locals {
  project_name = "${var.project_prefix}-wms"
  repository   = "https://github.com/LucasValbuena1/PROVESI_SAS.git"

  common_tags = {
    Project     = local.project_name
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}

# ==================== DATA SOURCES ====================

# AMI de Ubuntu 24.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC por defecto
data "aws_vpc" "default" {
  default = true
}

# ==================== SECURITY GROUPS ====================

# Grupo de seguridad para SSH
resource "aws_security_group" "ssh" {
  name        = "${var.project_prefix}-ssh"
  description = "Allow SSH access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-ssh"
  })
}

# Grupo de seguridad para la aplicación (puerto 8000)
resource "aws_security_group" "app" {
  name        = "${var.project_prefix}-app"
  description = "Allow application traffic on port 8000"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP Application"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Standard"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-app"
  })
}

# Grupo de seguridad para PostgreSQL
resource "aws_security_group" "postgres" {
  name        = "${var.project_prefix}-postgres"
  description = "Allow PostgreSQL access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-postgres"
  })
}

# Grupo de seguridad para MongoDB
resource "aws_security_group" "mongodb" {
  name        = "${var.project_prefix}-mongodb"
  description = "Allow MongoDB access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "MongoDB"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-mongodb"
  })
}

# ==================== EC2 INSTANCES ====================

# -------------------- PostgreSQL Database --------------------
resource "aws_instance" "postgres_db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.db_instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [
    aws_security_group.postgres.id,
    aws_security_group.ssh.id
  ]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    exec > /var/log/user-data.log 2>&1

    export DEBIAN_FRONTEND=noninteractive

    # Actualizar sistema
    apt-get update -y
    apt-get upgrade -y

    # Instalar PostgreSQL 16
    apt-get install -y postgresql postgresql-contrib

    # Esperar a que PostgreSQL esté listo
    sleep 5

    # Obtener versión de PostgreSQL instalada
    PG_VERSION=$(psql --version | awk '{print $3}' | cut -d. -f1)
    PG_CONF_DIR="/etc/postgresql/$PG_VERSION/main"

    # Crear usuario y base de datos
    sudo -u postgres psql -c "CREATE USER provesi WITH PASSWORD '1234' CREATEDB;"
    sudo -u postgres psql -c "CREATE DATABASE provesi_orders OWNER provesi;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE provesi_orders TO provesi;"

    # Configurar acceso remoto
    echo "host all all 0.0.0.0/0 md5" | sudo tee -a $PG_CONF_DIR/pg_hba.conf
    
    # Configurar PostgreSQL para escuchar en todas las interfaces
    sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF_DIR/postgresql.conf
    echo "max_connections = 200" | sudo tee -a $PG_CONF_DIR/postgresql.conf

    # Reiniciar PostgreSQL
    sudo systemctl restart postgresql
    sudo systemctl enable postgresql

    echo "PostgreSQL configurado exitosamente"
  EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-postgres-db"
    Role = "database-postgresql"
  })
}

# -------------------- MongoDB Database --------------------
resource "aws_instance" "mongodb" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.db_instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [
    aws_security_group.mongodb.id,
    aws_security_group.ssh.id
  ]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    exec > /var/log/user-data.log 2>&1

    export DEBIAN_FRONTEND=noninteractive

    # Actualizar sistema
    apt-get update -y
    apt-get upgrade -y

    # Instalar dependencias
    apt-get install -y gnupg curl

    # Agregar repositorio de MongoDB 7.0
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
      gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
      tee /etc/apt/sources.list.d/mongodb-org-7.0.list

    # Instalar MongoDB
    apt-get update -y
    apt-get install -y mongodb-org

    # Configurar MongoDB para escuchar en todas las interfaces
    sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

    # Iniciar y habilitar MongoDB
    systemctl daemon-reload
    systemctl enable mongod
    systemctl start mongod

    # Esperar a que MongoDB esté listo
    sleep 10

    echo "MongoDB configurado exitosamente"
  EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-mongodb"
    Role = "database-mongodb"
  })
}

# -------------------- Application Server --------------------
resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [
    aws_security_group.app.id,
    aws_security_group.ssh.id
  ]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    exec > /var/log/user-data.log 2>&1

    export DEBIAN_FRONTEND=noninteractive

    # Variables de entorno para las bases de datos
    POSTGRES_HOST="${aws_instance.postgres_db.private_ip}"
    MONGODB_HOST="${aws_instance.mongodb.private_ip}"

    # Guardar variables de entorno
    cat >> /etc/environment <<EOF
    POSTGRES_HOST=$POSTGRES_HOST
    MONGODB_HOST=$MONGODB_HOST
    DJANGO_SETTINGS_MODULE=provesi_wms.settings
    EOF

    # Actualizar sistema
    apt-get update -y
    apt-get upgrade -y

    # Instalar dependencias del sistema
    apt-get install -y \
      python3 \
      python3-pip \
      python3-venv \
      python3-dev \
      git \
      build-essential \
      libpq-dev \
      nginx \
      supervisor

    # Crear directorio de la aplicación
    mkdir -p /opt/provesi
    cd /opt/provesi

    # Clonar repositorio
    git clone ${local.repository} app
    cd app

    # Crear entorno virtual
    python3 -m venv venv
    source venv/bin/activate

    # Instalar dependencias de Python
    pip install --upgrade pip
    pip install -r requirements.txt
    pip install gunicorn

    # Crear archivo de configuración de Django para producción
    cat > /opt/provesi/app/provesi_wms/settings_prod.py <<EOF
    from .settings import *
    import os

    DEBUG = False
    ALLOWED_HOSTS = ['*']

    # PostgreSQL Configuration
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': 'provesi_orders',
            'USER': 'provesi',
            'PASSWORD': '1234',
            'HOST': os.environ.get('POSTGRES_HOST', 'localhost'),
            'PORT': '5432',
        },
    }
    EOF

    # Crear archivo de conexión MongoDB para producción
    cat > /opt/provesi/app/provesi_wms/mongodb_prod.py <<EOF
    import mongoengine
    import os

    def connect_mongodb():
        mongodb_host = os.environ.get('MONGODB_HOST', 'localhost')
        mongoengine.connect(
            db='provesi_clients',
            host=mongodb_host,
            port=27017
        )
        print(f"MongoDB conectado a {mongodb_host}:27017")
    EOF

    # Actualizar settings.py para usar variables de entorno
    cat > /opt/provesi/app/provesi_wms/settings.py <<'SETTINGS'
    from pathlib import Path
    import os

    BASE_DIR = Path(__file__).resolve().parent.parent

    SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', 'django-insecure-provesi-wms-secret-key-2024-production')

    DEBUG = os.environ.get('DEBUG', 'False').lower() == 'true'

    ALLOWED_HOSTS = ['*']

    INSTALLED_APPS = [
        'django.contrib.contenttypes',
        'django.contrib.staticfiles',
        'django.contrib.sessions',
        'django.contrib.messages',
        'rest_framework',
        'apps.home',
        'apps.clients',
        'apps.orders',
        'apps.security',
    ]

    MIDDLEWARE = [
        'django.middleware.security.SecurityMiddleware',
        'django.contrib.sessions.middleware.SessionMiddleware',
        'django.middleware.common.CommonMiddleware',
        'django.middleware.csrf.CsrfViewMiddleware',
        'django.contrib.messages.middleware.MessageMiddleware',
        'django.middleware.clickjacking.XFrameOptionsMiddleware',
        'apps.security.middleware.MicroserviceSecurityMiddleware',
    ]

    ROOT_URLCONF = 'provesi_wms.urls'

    TEMPLATES = [
        {
            'BACKEND': 'django.template.backends.django.DjangoTemplates',
            'DIRS': [BASE_DIR / 'templates'],
            'APP_DIRS': True,
            'OPTIONS': {
                'context_processors': [
                    'django.template.context_processors.debug',
                    'django.template.context_processors.request',
                    'django.contrib.messages.context_processors.messages',
                ],
            },
        },
    ]

    WSGI_APPLICATION = 'provesi_wms.wsgi.application'

    # Database - PostgreSQL
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': 'provesi_orders',
            'USER': 'provesi',
            'PASSWORD': '1234',
            'HOST': os.environ.get('POSTGRES_HOST', 'localhost'),
            'PORT': '5432',
        },
    }

    DATABASE_ROUTERS = []

    AUTH_PASSWORD_VALIDATORS = []

    LANGUAGE_CODE = 'es-co'
    TIME_ZONE = 'America/Bogota'
    USE_I18N = True
    USE_TZ = True

    STATIC_URL = 'static/'
    STATIC_ROOT = BASE_DIR / 'staticfiles'
    STATICFILES_DIRS = []

    DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

    LOGGING = {
        'version': 1,
        'disable_existing_loggers': False,
        'handlers': {
            'console': {
                'class': 'logging.StreamHandler',
            },
            'file': {
                'class': 'logging.FileHandler',
                'filename': '/var/log/provesi/app.log',
            },
        },
        'root': {
            'handlers': ['console', 'file'],
            'level': 'INFO',
        },
    }

    MICROSERVICE_SERVICE_TOKEN = 'provesi_service_token_2024'
    SETTINGS

    # Actualizar mongodb.py para usar variables de entorno
    cat > /opt/provesi/app/provesi_wms/mongodb.py <<'MONGODB'
    import mongoengine
    import os

    def connect_mongodb():
        mongodb_host = os.environ.get('MONGODB_HOST', 'localhost')
        try:
            mongoengine.connect(
                db='provesi_clients',
                host=mongodb_host,
                port=27017
            )
            print(f"MongoDB conectado a {mongodb_host}:27017")
        except Exception as e:
            print(f"Error conectando a MongoDB: {e}")
    MONGODB

    # Crear directorio de logs
    mkdir -p /var/log/provesi
    touch /var/log/provesi/app.log
    chown -R www-data:www-data /var/log/provesi

    # Esperar a que las bases de datos estén listas
    echo "Esperando a que las bases de datos estén disponibles..."
    sleep 60

    # Cargar variables de entorno
    export POSTGRES_HOST="$POSTGRES_HOST"
    export MONGODB_HOST="$MONGODB_HOST"

    # Aplicar migraciones
    cd /opt/provesi/app
    source venv/bin/activate
    python manage.py migrate --noinput || echo "Migraciones fallaron, reintentando..."
    sleep 10
    python manage.py migrate --noinput

    # Crear directorio de archivos estáticos
    mkdir -p /opt/provesi/app/staticfiles
    python manage.py collectstatic --noinput || true

    # Configurar permisos
    chown -R www-data:www-data /opt/provesi

    # Configurar Supervisor para ejecutar la aplicación
    cat > /etc/supervisor/conf.d/provesi.conf <<EOF
    [program:provesi]
    command=/opt/provesi/app/venv/bin/uvicorn provesi_wms.asgi:application --host 0.0.0.0 --port 8000 --workers 4
    directory=/opt/provesi/app
    user=www-data
    autostart=true
    autorestart=true
    redirect_stderr=true
    stdout_logfile=/var/log/provesi/uvicorn.log
    environment=POSTGRES_HOST="$POSTGRES_HOST",MONGODB_HOST="$MONGODB_HOST"
    EOF

    # Configurar Nginx como proxy reverso
    cat > /etc/nginx/sites-available/provesi <<EOF
    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://127.0.0.1:8000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_cache_bypass \$http_upgrade;
            proxy_read_timeout 86400;
        }

        location /static/ {
            alias /opt/provesi/app/staticfiles/;
        }
    }
    EOF

    # Habilitar sitio de Nginx
    ln -sf /etc/nginx/sites-available/provesi /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Reiniciar servicios
    systemctl restart supervisor
    systemctl restart nginx
    systemctl enable supervisor
    systemctl enable nginx

    # Iniciar la aplicación con supervisor
    supervisorctl reread
    supervisorctl update
    supervisorctl start provesi

    echo "==================================="
    echo "PROVESI WMS desplegado exitosamente"
    echo "PostgreSQL: $POSTGRES_HOST:5432"
    echo "MongoDB: $MONGODB_HOST:27017"
    echo "Aplicación: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"
    echo "==================================="
  EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-app"
    Role = "application"
  })

  depends_on = [
    aws_instance.postgres_db,
    aws_instance.mongodb
  ]
}

# ==================== OUTPUTS ====================

output "app_public_ip" {
  description = "Public IP address of the application server"
  value       = aws_instance.app.public_ip
}

output "app_url" {
  description = "URL to access the application"
  value       = "http://${aws_instance.app.public_ip}:8000"
}

output "app_url_nginx" {
  description = "URL to access the application via Nginx"
  value       = "http://${aws_instance.app.public_ip}"
}

output "postgres_private_ip" {
  description = "Private IP address of PostgreSQL database"
  value       = aws_instance.postgres_db.private_ip
}

output "postgres_public_ip" {
  description = "Public IP address of PostgreSQL database (for debugging)"
  value       = aws_instance.postgres_db.public_ip
}

output "mongodb_private_ip" {
  description = "Private IP address of MongoDB database"
  value       = aws_instance.mongodb.private_ip
}

output "mongodb_public_ip" {
  description = "Public IP address of MongoDB database (for debugging)"
  value       = aws_instance.mongodb.public_ip
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    app      = "ssh -i <your-key.pem> ubuntu@${aws_instance.app.public_ip}"
    postgres = "ssh -i <your-key.pem> ubuntu@${aws_instance.postgres_db.public_ip}"
    mongodb  = "ssh -i <your-key.pem> ubuntu@${aws_instance.mongodb.public_ip}"
  }
}

output "api_endpoints" {
  description = "API endpoints"
  value = {
    home     = "http://${aws_instance.app.public_ip}:8000/"
    clients  = "http://${aws_instance.app.public_ip}:8000/clients/"
    orders   = "http://${aws_instance.app.public_ip}:8000/orders/"
    api_docs = "http://${aws_instance.app.public_ip}:8000/api/docs"
  }
}
