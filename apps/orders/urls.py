from django.urls import path
from .views import (
    order_status,
    health,
    order_lookup,
    health_cached,
    orders_summary,
)

urlpatterns = [
    # Página HTML
    path("", order_lookup, name="order-lookup"),

    # APIs existentes
    path("api/v1/orders/<str:order_number>/status", order_status, name="order-status"),
    path("health", health, name="health"),

    # Nuevos endpoints para pruebas de disponibilidad
    path("api/health-cached", health_cached, name="health-cached"),
    path("api/v1/orders/summary", orders_summary, name="orders-summary"),
]
