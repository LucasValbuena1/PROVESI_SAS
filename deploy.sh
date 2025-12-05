#!/bin/bash
# ============================================================
# PROVESI WMS - Script de Despliegue Rápido para AWS CloudShell
# ============================================================
# 
# Uso: 
#   curl -sSL https://raw.githubusercontent.com/LucasValbuena1/PROVESI_SAS/main/deploy.sh | bash
#
# O descargarlo y ejecutarlo:
#   wget https://raw.githubusercontent.com/LucasValbuena1/PROVESI_SAS/main/deploy.sh
#   chmod +x deploy.sh
#   ./deploy.sh
# ============================================================

set -e

echo "=========================================="
echo "  PROVESI WMS - Despliegue en AWS"
echo "=========================================="
echo ""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar que estamos en AWS CloudShell o que AWS CLI está configurado
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI no está configurado. Por favor configura tus credenciales."
    exit 1
fi

log_info "AWS CLI configurado correctamente"

# Instalar Terraform si no está disponible
if ! command -v terraform &> /dev/null; then
    log_info "Instalando Terraform..."
    sudo yum install -y yum-utils 2>/dev/null || sudo apt-get update
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo 2>/dev/null || true
    sudo yum -y install terraform 2>/dev/null || {
        # Fallback para sistemas basados en Debian
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install terraform
    }
    log_info "Terraform instalado correctamente"
else
    log_info "Terraform ya está instalado: $(terraform --version | head -1)"
fi

# Crear directorio de trabajo
WORK_DIR=~/provesi-deployment
mkdir -p $WORK_DIR
cd $WORK_DIR

log_info "Directorio de trabajo: $WORK_DIR"

# Descargar archivos del repositorio
log_info "Descargando configuración de Terraform..."

# Intentar descargar del repositorio
if curl -sSL -o deployment.tf https://raw.githubusercontent.com/LucasValbuena1/PROVESI_SAS/main/deployment.tf 2>/dev/null; then
    log_info "Archivo deployment.tf descargado"
else
    log_warn "No se pudo descargar del repositorio. Creando archivo localmente..."
    # Aquí se crearía el archivo si no se puede descargar
fi

# Inicializar Terraform
log_info "Inicializando Terraform..."
terraform init

# Mostrar plan
log_info "Generando plan de despliegue..."
terraform plan -out=tfplan

echo ""
echo "=========================================="
echo "  RESUMEN DEL DESPLIEGUE"
echo "=========================================="
echo ""
echo "Se crearán los siguientes recursos:"
echo "  - 1 EC2 para PostgreSQL (t3.micro)"
echo "  - 1 EC2 para MongoDB (t3.micro)"
echo "  - 1 EC2 para la Aplicación (t3.small)"
echo "  - 4 Security Groups"
echo ""
echo "Costo estimado: ~\$37/mes"
echo ""
echo "=========================================="

# Confirmar despliegue
read -p "¿Deseas continuar con el despliegue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_warn "Despliegue cancelado"
    exit 0
fi

# Aplicar configuración
log_info "Desplegando infraestructura..."
terraform apply tfplan

echo ""
echo "=========================================="
echo "  DESPLIEGUE COMPLETADO"
echo "=========================================="
echo ""

# Mostrar outputs
terraform output

echo ""
log_info "La aplicación estará disponible en 3-5 minutos"
echo ""

# Guardar información de acceso
cat > access_info.txt <<EOF
PROVESI WMS - Información de Acceso
===================================
Fecha: $(date)

URLs de la Aplicación:
$(terraform output -json api_endpoints | jq -r 'to_entries[] | "  \(.key): \(.value)"')

IPs:
  Aplicación: $(terraform output -raw app_public_ip)
  PostgreSQL: $(terraform output -raw postgres_private_ip)
  MongoDB: $(terraform output -raw mongodb_private_ip)

Para destruir la infraestructura:
  cd $WORK_DIR && terraform destroy
EOF

log_info "Información guardada en: $WORK_DIR/access_info.txt"

echo ""
echo "=========================================="
echo "  PRÓXIMOS PASOS"
echo "=========================================="
echo ""
echo "1. Espera 3-5 minutos para que la aplicación esté lista"
echo ""
echo "2. Accede a la aplicación:"
echo "   $(terraform output -raw app_url)"
echo ""
echo "3. Para ver los logs:"
echo "   ssh ubuntu@$(terraform output -raw app_public_ip)"
echo "   sudo tail -f /var/log/provesi/uvicorn.log"
echo ""
echo "4. Para destruir la infraestructura cuando termines:"
echo "   cd $WORK_DIR && terraform destroy"
echo ""
echo "=========================================="
