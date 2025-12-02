# PROVESI WMS

Sistema de gestión de órdenes y clientes con arquitectura de microservicios.

## Arquitectura

```
┌─────────────────────────────────────────────────────┐
│                      PROVESI WMS                    │
│                      Puerto 8000                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│   ┌─────────────────┐         ┌─────────────────┐   │
│   │    CLIENTES     │         │    ÓRDENES      │   │
│   │    (FastAPI)    │◄───────►│    (FastAPI)    │   │
│   └────────┬────────┘         └────────┬────────┘   │
│            │                           │            │
│            ▼                           ▼            │
│   ┌─────────────────┐         ┌─────────────────┐   │
│   │    MongoDB      │         │   PostgreSQL    │   │
│   │ provesi_clients │         │ provesi_orders  │   │
│   └─────────────────┘         └─────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Requisitos

- Python 3.10+
- PostgreSQL 14+
- MongoDB 6+

---

## Instalación de Requisitos

### PostgreSQL

#### Mac
```bash
brew install postgresql@14
brew services start postgresql@14
```

#### Ubuntu/Debian
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

#### Windows
1. Descargar desde https://www.postgresql.org/download/windows/
2. Ejecutar el instalador y seguir las instrucciones
3. Recordar la contraseña del usuario `postgres`

---

### MongoDB

#### Mac
```bash
brew tap mongodb/brew
brew install mongodb-community
brew services start mongodb-community
```

#### Ubuntu/Debian
```bash
# Importar clave GPG
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

# Agregar repositorio
echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# Instalar
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod
```

#### Windows
1. Descargar desde https://www.mongodb.com/try/download/community
2. Ejecutar el instalador
3. Seleccionar "Complete" y marcar "Install MongoDB as a Service"
4. Completar la instalación

---

## Instalación del Proyecto

### 1. Clonar e instalar dependencias

```bash
git clone https://github.com/LucasValbuena1/PROVESI_SAS.git
cd PROVESI_SAS

python -m venv .venv

# Windows
.venv\Scripts\activate

# Mac/Linux
source .venv/bin/activate

pip install -r requirements.txt
```

### 2. Crear base de datos PostgreSQL

#### Mac/Linux
```bash
psql postgres -c "CREATE USER provesi WITH PASSWORD '1234';"
psql postgres -c "CREATE DATABASE provesi_wms OWNER provesi;"
psql postgres -c "CREATE DATABASE provesi_orders OWNER provesi;"
```

#### Windows (PowerShell como Administrador)
```powershell
psql -U postgres -c "CREATE USER provesi WITH PASSWORD '1234';"
psql -U postgres -c "CREATE DATABASE provesi_wms OWNER provesi;"
psql -U postgres -c "CREATE DATABASE provesi_orders OWNER provesi;"
```

### 3. Aplicar migraciones

```bash
python manage.py migrate --database=default
python manage.py migrate --database=orders_db
```

**Nota:** MongoDB no requiere migraciones. La base de datos `provesi_clients` se crea automáticamente.

### 4. Ejecutar la aplicación

```bash
uvicorn provesi_wms.asgi:application --reload
```

Abrir http://127.0.0.1:8000

---

## URLs Principales

| URL | Descripción |
|-----|-------------|
| `/` | Inicio |
| `/clients/` | Gestión de clientes (MongoDB) |
| `/orders/` | Gestión de órdenes (PostgreSQL) |
| `/orders/returns/` | Devoluciones |
| `/api/docs` | Documentación Swagger |
| `/api/clients/` | API REST de clientes |
| `/api/orders/` | API REST de órdenes |

---

## Verificar Servicios

### Verificar PostgreSQL

#### Mac/Linux
```bash
psql postgres -c "SELECT version();"
```

#### Windows
```powershell
psql -U postgres -c "SELECT version();"
```

### Verificar MongoDB

#### Mac/Linux
```bash
mongosh --eval "db.version()"
```

#### Windows
```powershell
mongosh --eval "db.version()"
```

---

## Solución de Problemas

### PostgreSQL no inicia

#### Mac
```bash
brew services restart postgresql@14
```

#### Linux
```bash
sudo systemctl restart postgresql
```

#### Windows
```powershell
net stop postgresql-x64-14
net start postgresql-x64-14
```

### MongoDB no inicia

#### Mac
```bash
brew services restart mongodb-community
```

#### Linux
```bash
sudo systemctl restart mongod
```

#### Windows
```powershell
net stop MongoDB
net start MongoDB
```

### Error de conexión a PostgreSQL
Verificar que el usuario y base de datos existen:
```bash
psql postgres -c "\du"  # Lista usuarios
psql postgres -c "\l"   # Lista bases de datos
```

### Error de conexión a MongoDB
Verificar que MongoDB está corriendo:
```bash
mongosh --eval "db.adminCommand('ping')"
```

---

## Tecnologías

| Componente | Tecnología |
|------------|------------|
| Backend | Django 5.1 + FastAPI |
| Base de datos SQL | PostgreSQL 14+ |
| Base de datos NoSQL | MongoDB 6+ |
| API | REST con FastAPI |
| Servidor ASGI | Uvicorn |