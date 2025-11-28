from django.shortcuts import render, get_object_or_404, redirect
from django.http import JsonResponse
from django.views.decorators.cache import never_cache
from django.contrib import messages
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from .models import Order, OrderStatus
import re


def order_lookup(request):
    q = request.GET.get("q", "").strip()
    order, not_found = None, False
    if q:
        if not re.match(r"^[A-Za-z0-9\-]+$", q):
            return Response({"error": "Orden invalida"}, status=status.HTTP_400_BAD_REQUEST)
        order = Order.objects.only("order_number", "status", "updated_at")\
                              .filter(order_number__iexact=q).first()
        if not order:
            not_found = True
    return render(request, "orders/lookup.html", {
        "query": q,
        "order": order,
        "not_found": not_found,
    })


def order_list(request):
    """Lista todas las órdenes"""
    orders = Order.objects.all().order_by('-updated_at')
    return render(request, "orders/list.html", {"orders": orders})


def order_create(request):
    """Crear una nueva orden"""
    if request.method == "POST":
        order_number = request.POST.get("order_number", "").strip()
        status_value = request.POST.get("status", OrderStatus.RECEIVED)
        
        # Validar formato
        if not order_number:
            messages.error(request, "El código del pedido es requerido.")
            return render(request, "orders/create.html", {"statuses": OrderStatus.choices})
        
        if not re.match(r"^[A-Za-z0-9\-]+$", order_number):
            messages.error(request, "El código solo puede contener letras, números y guiones.")
            return render(request, "orders/create.html", {"statuses": OrderStatus.choices})
        
        # Verificar si ya existe
        if Order.objects.filter(order_number__iexact=order_number).exists():
            messages.error(request, f"Ya existe una orden con el código '{order_number}'.")
            return render(request, "orders/create.html", {"statuses": OrderStatus.choices})
        
        # Crear la orden
        Order.objects.create(order_number=order_number, status=status_value)
        messages.success(request, f"Orden '{order_number}' creada exitosamente.")
        return redirect("order-list")
    
    return render(request, "orders/create.html", {"statuses": OrderStatus.choices})


def order_edit(request, order_number):
    """Editar una orden existente"""
    order = get_object_or_404(Order, order_number=order_number)
    
    if request.method == "POST":
        new_order_number = request.POST.get("order_number", "").strip()
        status_value = request.POST.get("status", order.status)
        
        # Validar formato
        if not new_order_number:
            messages.error(request, "El código del pedido es requerido.")
            return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices})
        
        if not re.match(r"^[A-Za-z0-9\-]+$", new_order_number):
            messages.error(request, "El código solo puede contener letras, números y guiones.")
            return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices})
        
        # Verificar duplicados (si cambió el número)
        if new_order_number.lower() != order.order_number.lower():
            if Order.objects.filter(order_number__iexact=new_order_number).exists():
                messages.error(request, f"Ya existe una orden con el código '{new_order_number}'.")
                return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices})
        
        # Actualizar la orden
        order.order_number = new_order_number
        order.status = status_value
        order.save()
        messages.success(request, f"Orden '{new_order_number}' actualizada exitosamente.")
        return redirect("order-list")
    
    return render(request, "orders/edit.html", {"order": order, "statuses": OrderStatus.choices})


def order_delete(request, order_number):
    """Eliminar una orden"""
    order = get_object_or_404(Order, order_number=order_number)
    
    if request.method == "POST":
        order_num = order.order_number
        order.delete()
        messages.success(request, f"Orden '{order_num}' eliminada exitosamente.")
        return redirect("order-list")
    
    return render(request, "orders/delete.html", {"order": order})


@api_view(["GET"])
@never_cache
def order_status(request, order_number: str):
    order = get_object_or_404(
        Order.objects.only("order_number", "status", "updated_at"),
        order_number=order_number
    )
    return JsonResponse({
        "order_number": order.order_number,
        "status": order.status,
        "last_updated": order.updated_at.isoformat()
    })


def health(request):
    return JsonResponse({"ok": True})