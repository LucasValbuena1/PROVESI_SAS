"""
URL configuration for provesi_wms project.

For details, see:
https://docs.djangoproject.com/en/5.1/topics/http/urls/
"""
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path("admin/", admin.site.urls),

    # Rutas del módulo de órdenes (incluye HTML y APIs)
    path("", include("apps.orders.urls")),

    # Inventario (si tu app define sus urls)
    path("inventario/", include("inventario.urls")),
]
