"""
Vistas del microservicio de Órdenes.

Base de datos: PostgreSQL (default)
Comunicación con Clientes: MongoDB via secure_client_service
"""

import logging
import re
from django.shortcuts import render, redirect
from django.http import JsonResponse
from django.views.decorators.cache import never_cache
from django.contrib import messages
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from .models import Order, OrderStatus
from apps.security.services import secure_client_service
from apps.security.decorators import audit_access

logger = logging.getLogger(__name__)


def get_all_clients():
    """Obtiene todos los clientes desde MongoDB."""
    from apps.clients.models import Client
    
    try:
        clients = Client.objects.all().order_by('name')
        logger.info(f"[ORDERS] Obtenidos {clients.count()} clientes desde MongoDB")
        return list(clients)
    except Exception as e:
        logger.error(f"[ORDERS] Error obteniendo clientes: {str(e)}")
        return []


def enrich_orders_with_clients(orders):
    """Enriquece órdenes con información de clientes desde MongoDB."""
    client_ids = list(set(order.client_id for order in orders if order.client_id))
    
    if not client_ids:
        for order in orders:
            order._client_cache = None
        return orders
    
    clients_map = secure_client_service.get_clients_for_orders(client_ids)
    
    for order in orders:
        if order.client_id and order.client_id in clients_map:
            client_data = clients_map[order.client_id]
            order._client_cache = type('Client', (), {
                'id': client_data.get('id'),
                'name': client_data.get('name'),
                'email': client_data.get('email'),
            })()
        else:
            order._client_cache = None
    
    return orders


@audit_access('order')
def order_lookup(request):
    """Búsqueda de orden por código."""
    q = request.GET.get("q", "").strip()
    order, not_found = None, False
    
    if q:
        if not re.match(r"^[A-Za-z0-9\-]+$", q):
            messages.error(request, "Código de orden inválido.")
            return render(request, "orders/lookup.html", {"query": q, "not_found": True})
        
        order = Order.objects.filter(order_number__iexact=q).first()
        
        if order:
            if order.client_id:
                client_data = secure_client_service.get_client_secure(order.client_id)
                if client_data:
                    order._client_cache = type('Client', (), {
                        'id': client_data.get('id'),
                        'name': client_data.get('name'),
                        'email': client_data.get('email'),
                    })()
                else:
                    order._client_cache = None
            else:
                order._client_cache = None
        else:
            not_found = True
    
    return render(request, "orders/lookup.html", {
        "query": q,
        "order": order,
        "not_found": not_found,
    })


@audit_access('order')
def order_list(request):
    """Lista todas las órdenes."""
    orders = list(Order.objects.all().order_by('-updated_at'))
    enrich_orders_with_clients(orders)
    
    returns_count = Order.objects.filter(status=OrderStatus.RETURNED).count()
    
    return render(request, "orders/list.html", {
        "orders": orders,
        "returns_count": returns_count
    })


@audit_access('order')
def order_create(request):
    """Crear una nueva orden."""
    clients = get_all_clients()
    
    if request.method == "POST":
        order_number = request.POST.get("order_number", "").strip()
        status_value = request.POST.get("status", OrderStatus.RECEIVED)
        client_id = request.POST.get("client", "").strip()
        
        if not order_number:
            messages.error(request, "El código del pedido es requerido.")
            return render(request, "orders/create.html", {"statuses": OrderStatus.choices, "clients": clients})
        
        if not re.match(r"^[A-Za-z0-9\-]+$", order_number):
            messages.error(request, "El código solo puede contener letras, números y guiones.")
            return render(request, "orders/create.html", {"statuses": OrderStatus.choices, "clients": clients})
        
        if Order.objects.filter(order_number__iexact=order_number).exists():
            messages.error(request, f"Ya existe una orden con el código '{order_number}'.")
            return render(request, "orders/create.html", {"statuses": OrderStatus.choices, "clients": clients})
        
        if client_id:
            client_data = secure_client_service.get_client_secure(client_id)
            if not client_data:
                messages.error(request, "El cliente seleccionado no existe.")
                return render(request, "orders/create.html", {"statuses": OrderStatus.choices, "clients": clients})
        
        order = Order(
            order_number=order_number,
            status=status_value,
            client_id=client_id if client_id else None
        )
        order.save()
        
        logger.info(f"[ORDERS] Orden {order_number} creada con cliente {client_id}")
        messages.success(request, f"Orden '{order_number}' creada exitosamente.")
        return redirect("order-list")
    
    return render(request, "orders/create.html", {"statuses": OrderStatus.choices, "clients": clients})


@audit_access('order')
def order_edit(request, order_number):
    """Editar una orden existente."""
    try:
        order = Order.objects.get(order_number=order_number)
    except Order.DoesNotExist:
        messages.error(request, f"No se encontró la orden '{order_number}'.")
        return redirect("order-list")
    
    clients = get_all_clients()
    
    if order.client_id:
        client_data = secure_client_service.get_client_secure(order.client_id)
        if client_data:
            order._client_cache = type('Client', (), {
                'id': client_data.get('id'),
                'name': client_data.get('name'),
            })()
    
    if request.method == "POST":
        new_order_number = request.POST.get("order_number", "").strip()
        status_value = request.POST.get("status", order.status)
        client_id = request.POST.get("client", "").strip()
        return_reason = request.POST.get("return_reason", "").strip()
        
        if not new_order_number:
            messages.error(request, "El código del pedido es requerido.")
            return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices, "clients": clients})
        
        if not re.match(r"^[A-Za-z0-9\-]+$", new_order_number):
            messages.error(request, "El código solo puede contener letras, números y guiones.")
            return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices, "clients": clients})
        
        if new_order_number.lower() != order.order_number.lower():
            if Order.objects.filter(order_number__iexact=new_order_number).exists():
                messages.error(request, f"Ya existe una orden con el código '{new_order_number}'.")
                return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices, "clients": clients})
        
        if client_id:
            client_data = secure_client_service.get_client_secure(client_id)
            if not client_data:
                messages.error(request, "El cliente seleccionado no existe.")
                return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices, "clients": clients})
        
        if status_value == OrderStatus.RETURNED and not return_reason:
            messages.error(request, "Debe ingresar una razón de devolución.")
            return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices, "clients": clients})
        
        order.order_number = new_order_number
        order.status = status_value
        order.client_id = client_id if client_id else None
        
        if status_value == OrderStatus.RETURNED:
            order.return_reason = return_reason
            if not order.returned_at:
                order.returned_at = timezone.now()
        else:
            order.return_reason = None
            order.returned_at = None
        
        order.save()
        
        logger.info(f"[ORDERS] Orden {new_order_number} actualizada - Estado: {status_value}")
        messages.success(request, f"Orden '{new_order_number}' actualizada exitosamente.")
        return redirect("order-list")
    
    return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices, "clients": clients})


@audit_access('order')
def order_delete(request, order_number):
    """Eliminar una orden."""
    try:
        order = Order.objects.get(order_number=order_number)
    except Order.DoesNotExist:
        messages.error(request, f"No se encontró la orden '{order_number}'.")
        return redirect("order-list")
    
    if order.client_id:
        client_data = secure_client_service.get_client_secure(order.client_id)
        if client_data:
            order._client_cache = type('Client', (), {
                'id': client_data.get('id'),
                'name': client_data.get('name'),
            })()
    
    if request.method == "POST":
        order_num = order.order_number
        order.delete()
        
        logger.info(f"[ORDERS] Orden {order_num} eliminada")
        messages.success(request, f"Orden '{order_num}' eliminada exitosamente.")
        return redirect("order-list")
    
    return render(request, "orders/delete.html", {"order": order})


@audit_access('order')
def returns_list(request):
    """Lista todas las órdenes devueltas con sus razones."""
    orders = list(
        Order.objects.filter(status=OrderStatus.RETURNED)
        .order_by('-returned_at', '-updated_at')
    )
    
    enrich_orders_with_clients(orders)
    
    logger.info(f"[ORDERS] Listadas {len(orders)} devoluciones")
    return render(request, "orders/returns.html", {"orders": orders})


@api_view(["GET"])
@never_cache
@audit_access('order')
def order_status_api(request, order_number: str):
    """API para obtener estado de una orden."""
    try:
        order = Order.objects.get(order_number=order_number)
    except Order.DoesNotExist:
        return Response({"error": "Orden no encontrada"}, status=status.HTTP_404_NOT_FOUND)
    
    client_name = None
    if order.client_id:
        client_data = secure_client_service.get_client_secure(order.client_id)
        if client_data:
            client_name = client_data.get('name')
    
    response_data = {
        "order_number": order.order_number,
        "status": order.status,
        "status_display": order.get_status_display(),
        "client": client_name,
        "client_id": order.client_id,
        "last_updated": order.updated_at.isoformat()
    }
    
    if order.status == OrderStatus.RETURNED:
        response_data["return_reason"] = order.return_reason
        response_data["returned_at"] = order.returned_at.isoformat() if order.returned_at else None
    
    return JsonResponse(response_data)


def health(request):
    """Health check."""
    from apps.clients.models import Client
    
    health_status = {
        "ok": True,
        "service": "orders",
        "databases": {},
    }
    
    try:
        Order.objects.first()
        health_status["databases"]["postgresql"] = "connected (provesi_orders)"
    except Exception as e:
        health_status["databases"]["postgresql"] = f"error: {str(e)}"
        health_status["ok"] = False
    
    try:
        Client.objects.first()
        health_status["databases"]["mongodb"] = "connected (provesi_clients)"
    except Exception as e:
        health_status["databases"]["mongodb"] = f"error: {str(e)}"
        health_status["ok"] = False
    
    return JsonResponse(health_status)