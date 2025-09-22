from django.urls import path
from .views import order_status, health, order_lookup

urlpatterns = [
    path("", order_lookup, name="order-lookup"),  # página HTML
    path("api/v1/orders/<str:order_number>/status", order_status, name="order-status"),
    path("health", health, name="health"),
]
