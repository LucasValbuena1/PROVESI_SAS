from django.urls import path
from inventario import views

urlpatterns = [
    path("",views.home, name="home")
]

