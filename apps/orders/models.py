from django.db import models


class OrderStatus(models.TextChoices):
    RECEIVED = "received", "Recibido"
    PICKING = "picking", "Alistamiento"
    PACKING = "packing", "Empaque"
    SHIPPED = "shipped", "Despachado"
    DELIVERED = "delivered", "Entregado"
    RETURNED = "returned", "Devuelto"
    CANCELLED = "cancelled", "Cancelado"


class Order(models.Model):
    """
    Modelo de Orden almacenado en PostgreSQL (provesi_orders).
    
    Nota: client_id es un CharField para almacenar el ObjectId de MongoDB.
    La relación se maneja a nivel de aplicación, no de base de datos.
    """
    order_number = models.CharField(max_length=32, unique=True, db_index=True)
    
    # Almacenamos el ID del cliente como string (ObjectId de MongoDB)
    client_id = models.CharField(max_length=24, null=True, blank=True, db_index=True)
    
    status = models.CharField(
        max_length=20, 
        choices=OrderStatus.choices, 
        default=OrderStatus.RECEIVED
    )
    
    # Campo para la razón de devolución
    return_reason = models.TextField(
        blank=True, 
        null=True,
        verbose_name="Razón de devolución"
    )
    returned_at = models.DateTimeField(
        blank=True, 
        null=True,
        verbose_name="Fecha de devolución"
    )
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'orders_order'
        ordering = ['-updated_at']

    def __str__(self):
        return f"{self.order_number} - {self.status}"

    def get_client(self):
        """Obtiene el cliente desde MongoDB."""
        if not self.client_id:
            return None
        
        from apps.clients.models import Client
        
        try:
            return Client.objects(id=self.client_id).first()
        except:
            return None

    @property
    def client(self):
        """Propiedad para acceder al cliente de forma conveniente."""
        if not hasattr(self, '_client_cache'):
            self._client_cache = self.get_client()
        return self._client_cache
    
    @property
    def is_returned(self):
        """Indica si la orden está devuelta."""
        return self.status == OrderStatus.RETURNED