from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.cache import never_cache
from django.contrib.auth.decorators import login_required
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from .models import Order
from provesi_wms.auth0backend import getRole
import re

@login_required
def order_lookup(request):
    try:
        role = getRole(request)
        if role not in ['Vendedor', 'Operario']:
            return render(request, 'orders/unauthorized.html', {'role': role})
    except Exception as e:
        return render(request, 'orders/unauthorized.html', {'error': str(e)})
    
    q = request.GET.get("q", "").strip()
    order, not_found = None, False
    if q:
        if not re.match(r"^[A-Za-z0-9\-]+$", q):
            return Response({"error":"Orden invalida"}, status=status.HTTP_400_BAD_REQUEST)
        order = Order.objects.only("order_number", "status", "updated_at")\
                              .filter(order_number__iexact=q).first()
        if not order:
            not_found = True
    return render(request, "orders/lookup.html", {
        "query": q, 
        "order": order, 
        "not_found": not_found,
        "user": request.user
    })

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