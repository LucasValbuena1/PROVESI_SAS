from django.db import models


class Client(models.Model):
    """
    Modelo de Cliente.
    
    Este modelo vive en la base de datos clients_db.
    """
    name = models.CharField(max_length=100)
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20, blank=True)
    address = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'clients_client'
        ordering = ['name']

    def __str__(self):
        return self.name

    def get_orders(self):
        """
        Obtiene las órdenes de este cliente desde la base de datos de órdenes.
        """
        # Importación tardía para evitar dependencias circulares
        from apps.orders.models import Order
        
        return Order.objects.using('orders_db').filter(client_id=self.id)

    @property
    def orders(self):
        """
        Propiedad para acceder a las órdenes de forma conveniente.
        """
        return self.get_orders()

    def orders_count(self):
        """
        Retorna el número de órdenes del cliente.
        """
        return self.get_orders().count()