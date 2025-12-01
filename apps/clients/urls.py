from django.urls import path
from .views import (
    client_list, client_create, client_detail, 
    client_edit, client_delete, client_api, health
)

urlpatterns = [
    path("", client_list, name="client-list"),
    path("create/", client_create, name="client-create"),
    path("<int:client_id>/", client_detail, name="client-detail"),
    path("<int:client_id>/edit/", client_edit, name="client-edit"),
    path("<int:client_id>/delete/", client_delete, name="client-delete"),
    
    # API interna
    path("api/v1/<int:client_id>/", client_api, name="client-api"),
    path("health", health, name="client-health"),
]