from django.urls import path
from .views import (
    client_list, client_create, client_detail,
    client_edit, client_delete, client_api, health
)

urlpatterns = [
    path("", client_list, name="client-list"),
    path("create/", client_create, name="client-create"),
    path("<str:client_id>/", client_detail, name="client-detail"),
    path("<str:client_id>/edit/", client_edit, name="client-edit"),
    path("<str:client_id>/delete/", client_delete, name="client-delete"),
    path("api/v1/<str:client_id>/", client_api, name="client-api"),
    path("health", health, name="client-health"),
]