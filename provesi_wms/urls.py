"""
URL configuration for provesi_wms project.
"""

from django.urls import path, include
from django.shortcuts import render

def home(request):
    return render(request, 'home/home.html')

urlpatterns = [
    path('', home, name='home'),
    path('clients/', include('apps.clients.urls')),
    path('orders/', include('apps.orders.urls')),
]