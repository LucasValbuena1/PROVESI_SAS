"""
ASGI config para PROVESI WMS.

Monta Django y FastAPI en la misma aplicación ASGI.
- /api/* -> FastAPI (APIs de microservicios)
- /* -> Django (vistas HTML, admin, etc.)
"""

import os
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'provesi_wms.settings')

# Inicializar Django primero
django_asgi_app = get_asgi_application()

# Conectar MongoDB
from provesi_wms.mongodb import connect_mongodb
connect_mongodb()

# Importar FastAPI después de inicializar Django
from provesi_wms.fastapi_app import fastapi_app


async def application(scope, receive, send):
    """
    Aplicación ASGI que enruta entre FastAPI y Django.
    
    - Rutas /api/* van a FastAPI
    - /openapi.json va a FastAPI
    - El resto va a Django
    """
    if scope["type"] == "http":
        path = scope.get("path", "")
        
        # Rutas API y OpenAPI van a FastAPI
        if path.startswith("/api/") or path == "/openapi.json":
            await fastapi_app(scope, receive, send)
        else:
            # El resto va a Django
            await django_asgi_app(scope, receive, send)
    else:
        # WebSockets y otros van a Django
        await django_asgi_app(scope, receive, send)