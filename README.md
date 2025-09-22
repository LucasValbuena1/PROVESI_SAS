# Provesi WMS (MVP de consulta de pedidos)

MVP de WMS para consultar el estado de un pedido en tiempo real (objetivo: respuesta ≤ 1 s bajo condiciones óptimas).

## Requisitos
- Python 3.12 (recomendado 3.12.11)
- PostgreSQL 16.x
- (Opcional) Java 17 y JMeter 5.6.3 para pruebas de rendimiento

## Setup (macOS / Linux)
```bash
# 1) Clonar
git clone https://github.com/tu-org/provesi-wms.git
cd provesi-wms

# 2) Entorno
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip wheel
pip install -r requirements.txt

# 3) Base de datos local
# Crea rol y DB (ajusta contraseña si quieres)
createuser -P provesi          # te pedirá una contraseña (utiliza '1234' que ya está puesta en settings.py)
createdb -O provesi provesi_wms

# 4) Migraciones
python manage.py makemigrations
python manage.py migrate

# 5) Datos de ejemplo
python manage.py shell << 'PY'
from apps.orders.models import Order, OrderStatus
Order.objects.get_or_create(order_number="PV-000001", defaults={"status": OrderStatus.PICKING})
print("Pedido de prueba creado.")
PY

# 6) Ejecutar
python manage.py runserver
