"""
Aplicación FastAPI integrada con Django.

Este archivo define la aplicación FastAPI que se monta junto con Django
para manejar las APIs de los microservicios.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Importar routers de cada microservicio
from apps.clients.api import router as clients_router
from apps.orders.api import router as orders_router

# Crear aplicación FastAPI
fastapi_app = FastAPI(
    title="PROVESI WMS API",
    description="API de microservicios para el sistema WMS de PROVESI",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
)

# Configurar CORS
fastapi_app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Registrar routers
fastapi_app.include_router(clients_router)
fastapi_app.include_router(orders_router)


@fastapi_app.get("/api/health")
def global_health():
    """Health check global de todos los microservicios."""
    from apps.clients.models import Client
    from apps.orders.models import Order
    
    services = {}
    
    # Verificar clientes
    try:
        Client.objects.using('clients_db').first()
        services["clients"] = {"status": "ok", "database": "connected"}
    except Exception as e:
        services["clients"] = {"status": "error", "database": str(e)}
    
    # Verificar órdenes
    try:
        Order.objects.using('orders_db').first()
        services["orders"] = {"status": "ok", "database": "connected"}
    except Exception as e:
        services["orders"] = {"status": "error", "database": str(e)}
    
    # Verificar seguridad
    try:
        from apps.security.crypto_service import crypto_service
        test = crypto_service.encrypt_aes("test")
        crypto_service.decrypt_aes(test)
        services["security"] = {"status": "ok", "crypto": "working"}
    except Exception as e:
        services["security"] = {"status": "error", "crypto": str(e)}
    
    all_ok = all(s["status"] == "ok" for s in services.values())
    
    return {
        "status": "ok" if all_ok else "degraded",
        "services": services
    }