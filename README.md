# PROVESI WMS

Sistema de gestión de órdenes y clientes con arquitectura de microservicios.

## Requisitos

- Python 3.10+
- PostgreSQL 14+

## Instalación

### 1. Clonar e instalar dependencias

```bash
git clone <url-del-repositorio>
cd PROVESI_SAS

python -m venv .venv

# Windows
.venv\Scripts\activate

# Mac/Linux
source .venv/bin/activate

pip install -r requirements.txt
```

### 2. Crear bases de datos

```bash
# Mac/Linux
psql postgres -c "CREATE USER provesi WITH PASSWORD '1234';"
psql postgres -c "CREATE DATABASE provesi_wms OWNER provesi;"
psql postgres -c "CREATE DATABASE provesi_clients OWNER provesi;"
psql postgres -c "CREATE DATABASE provesi_orders OWNER provesi;"

# Windows (desde CMD como administrador)
psql -U postgres -c "CREATE USER provesi WITH PASSWORD '1234';"
psql -U postgres -c "CREATE DATABASE provesi_wms OWNER provesi;"
psql -U postgres -c "CREATE DATABASE provesi_clients OWNER provesi;"
psql -U postgres -c "CREATE DATABASE provesi_orders OWNER provesi;"
```

### 3. Aplicar migraciones

```bash
python manage.py migrate --database=default
python manage.py migrate --database=clients_db
python manage.py migrate --database=orders_db
```

### 4. Ejecutar

```bash
python manage.py runserver
```

Abrir http://127.0.0.1:8000

## URLs principales

| URL | Descripción |
|-----|-------------|
| `/` | Inicio |
| `/orders/` | Gestión de órdenes |
| `/orders/returns/` | Devoluciones |
| `/clients/` | Gestión de clientes |
| `/orders/health` | Estado del sistema |