from django.db import models

# Create your models here.

class OrderStatus(models.TextChoices):
    RECEIVED="received","Recibido"
    PICKING="picking","Alistamiento"
    PACKING="packing","Empaque"
    SHIPPED="shipped","Despachado"
    DELIVERED="delivered","Entregado"
    CANCELLED="cancelled","Cancelado"

class Order(models.Model):
    order_number = models.CharField(max_length=32, unique=True, db_index=True)
    status = models.CharField(max_length=20, choices=OrderStatus.choices, default=OrderStatus.RECEIVED)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.order_number} - {self.status}"
