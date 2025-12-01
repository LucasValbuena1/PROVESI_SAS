from django.urls import path
from .views import (
    order_status_api, health, order_lookup, 
    order_list, order_create, order_edit, order_delete,
    returns_list
)

urlpatterns = [
    path("", order_list, name="order-list"),
    path("lookup/", order_lookup, name="order-lookup"),
    path("create/", order_create, name="order-create"),
    path("returns/", returns_list, name="returns-list"),  # Nueva ruta
    path("<str:order_number>/edit/", order_edit, name="order-edit"),
    path("<str:order_number>/delete/", order_delete, name="order-delete"),
    path("api/v1/orders/<str:order_number>/status", order_status_api, name="order-status"),
    path("health", health, name="health"),
]