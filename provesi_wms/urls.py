from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('orders/', include('apps.orders.urls')),
    path('clients/', include('apps.clients.urls')),
    path('', include('apps.home.urls')),
]