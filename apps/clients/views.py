"""
Vistas Django del microservicio de Clientes (MongoDB).
"""

import logging
from django.shortcuts import render, redirect
from django.http import JsonResponse
from django.contrib import messages
from bson import ObjectId
from .models import Client
from apps.security.services import secure_order_service
from apps.security.decorators import audit_access

logger = logging.getLogger(__name__)


def validate_object_id(client_id: str) -> bool:
    """Valida que el ID sea un ObjectId válido de MongoDB."""
    try:
        ObjectId(client_id)
        return True
    except:
        return False


class OrderProxy:
    """Clase proxy para representar una orden en los templates."""
    
    def __init__(self, data):
        self.order_number = data.get('order_number', '')
        self.status = data.get('status', '')
        self.status_display = data.get('status_display', self.status)
        self.updated_at = data.get('updated_at', '')
        self.client_id = data.get('client_id')
    
    def get_status_display(self):
        return self.status_display


@audit_access('client')
def client_list(request):
    """Lista todos los clientes con conteo de órdenes."""
    clients = list(Client.objects.all())
    
    # Obtener conteo de órdenes
    client_ids = [str(c.id) for c in clients]
    orders_counts = secure_order_service.get_orders_count_for_clients(client_ids)
    
    # Agregar conteo a cada cliente
    for client in clients:
        client.orders_count = orders_counts.get(str(client.id), 0)
    
    logger.info(f"[CLIENTS] Listados {len(clients)} clientes con conteo de órdenes")
    return render(request, "clients/list.html", {"clients": clients})


@audit_access('client')
def client_create(request):
    """Crear un nuevo cliente."""
    if request.method == "POST":
        name = request.POST.get("name", "").strip()
        email = request.POST.get("email", "").strip()
        phone = request.POST.get("phone", "").strip()
        address = request.POST.get("address", "").strip()
        
        if not name:
            messages.error(request, "El nombre es requerido.")
            return render(request, "clients/create.html")
        
        if not email:
            messages.error(request, "El email es requerido.")
            return render(request, "clients/create.html")
        
        if Client.objects(email__iexact=email).first():
            messages.error(request, f"Ya existe un cliente con el email '{email}'.")
            return render(request, "clients/create.html")
        
        client = Client(name=name, email=email, phone=phone, address=address)
        client.save()
        
        logger.info(f"[CLIENTS] Cliente '{name}' creado con ID {client.id}")
        messages.success(request, f"Cliente '{name}' creado exitosamente.")
        return redirect("client-list")
    
    return render(request, "clients/create.html")


@audit_access('client')
def client_detail(request, client_id):
    """Ver detalle de un cliente con sus órdenes."""
    if not validate_object_id(client_id):
        messages.error(request, "ID de cliente inválido.")
        return redirect("client-list")
    
    client = Client.objects(id=client_id).first()
    if not client:
        messages.error(request, "Cliente no encontrado.")
        return redirect("client-list")
    
    # Obtener órdenes del cliente
    orders_data = secure_order_service.get_orders_for_client(client_id)
    orders = [OrderProxy(data) for data in orders_data]
    
    logger.info(f"[CLIENTS] Detalle del cliente {client_id} con {len(orders)} órdenes")
    return render(request, "clients/detail.html", {"client": client, "orders": orders})


@audit_access('client')
def client_edit(request, client_id):
    """Editar un cliente existente."""
    if not validate_object_id(client_id):
        messages.error(request, "ID de cliente inválido.")
        return redirect("client-list")
    
    client = Client.objects(id=client_id).first()
    if not client:
        messages.error(request, "Cliente no encontrado.")
        return redirect("client-list")
    
    if request.method == "POST":
        name = request.POST.get("name", "").strip()
        email = request.POST.get("email", "").strip()
        phone = request.POST.get("phone", "").strip()
        address = request.POST.get("address", "").strip()
        
        if not name:
            messages.error(request, "El nombre es requerido.")
            return render(request, "clients/edit.html", {"client": client})
        
        if not email:
            messages.error(request, "El email es requerido.")
            return render(request, "clients/edit.html", {"client": client})
        
        if email.lower() != client.email.lower():
            if Client.objects(email__iexact=email).first():
                messages.error(request, f"Ya existe un cliente con el email '{email}'.")
                return render(request, "clients/edit.html", {"client": client})
        
        client.name = name
        client.email = email
        client.phone = phone
        client.address = address
        client.save()
        
        logger.info(f"[CLIENTS] Cliente {client_id} actualizado")
        messages.success(request, f"Cliente '{name}' actualizado exitosamente.")
        return redirect("client-list")
    
    return render(request, "clients/edit.html", {"client": client})


@audit_access('client')
def client_delete(request, client_id):
    """Eliminar un cliente."""
    if not validate_object_id(client_id):
        messages.error(request, "ID de cliente inválido.")
        return redirect("client-list")
    
    client = Client.objects(id=client_id).first()
    if not client:
        messages.error(request, "Cliente no encontrado.")
        return redirect("client-list")
    
    orders = secure_order_service.get_orders_for_client(client_id)
    orders_count = len(orders)
    
    if request.method == "POST":
        client_name = client.name
        
        # Desasociar órdenes
        from apps.orders.models import Order
        Order.objects.filter(client_id=client_id).update(client_id=None)
        
        client.delete()
        
        logger.info(f"[CLIENTS] Cliente '{client_name}' eliminado, {orders_count} órdenes desasociadas")
        messages.success(request, f"Cliente '{client_name}' eliminado exitosamente.")
        return redirect("client-list")
    
    return render(request, "clients/delete.html", {"client": client, "orders_count": orders_count})


def client_api(request, client_id):
    """API para obtener datos de un cliente."""
    if not validate_object_id(client_id):
        return JsonResponse({"error": "ID de cliente inválido"}, status=400)
    
    client = Client.objects(id=client_id).first()
    if not client:
        return JsonResponse({"error": "Cliente no encontrado"}, status=404)
    
    is_internal = getattr(request, 'is_internal_service', False)
    
    data = {
        "id": str(client.id),
        "name": client.name,
        "email": client.email if is_internal else "***",
        "phone": client.phone if is_internal else "***",
        "created_at": client.created_at.isoformat() if client.created_at else None
    }
    
    return JsonResponse(data)


def health(request):
    """Health check del microservicio de clientes."""
    from apps.orders.models import Order
    
    health_status = {
        "ok": True,
        "service": "clients",
        "databases": {},
        "security": "enabled"
    }
    
    # Verificar MongoDB
    try:
        Client.objects.first()
        health_status["databases"]["mongodb"] = "connected"
    except Exception as e:
        health_status["databases"]["mongodb"] = f"error: {str(e)}"
        health_status["ok"] = False
    
    # Verificar PostgreSQL (orders)
    try:
        Order.objects.first()
        health_status["databases"]["postgresql"] = "connected"
    except Exception as e:
        health_status["databases"]["postgresql"] = f"error: {str(e)}"
        health_status["ok"] = False
    
    return JsonResponse(health_status)