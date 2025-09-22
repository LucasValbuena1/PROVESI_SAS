from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.cache import never_cache
from rest_framework.decorators import api_view
from .models import Order

def order_lookup(request):
    q = request.GET.get("q", "").strip()
    order, not_found = None, False
    if q:
        order = Order.objects.only("order_number", "status", "updated_at")\
                              .filter(order_number__iexact=q).first()
        if not order:
            not_found = True
    return render(request, "orders/lookup.html", {"query": q, "order": order, "not_found": not_found})

@api_view(["GET"])
@never_cache
def order_status(request, order_number: str):
    order = get_object_or_404(
        Order.objects.only("order_number", "status", "updated_at"),
        order_number=order_number
    )
    return JsonResponse({
        "order_number": order.order_number,
        "status": order.status,                     # valor código
        "last_updated": order.updated_at.isoformat()
    })

def health(request):
    return JsonResponse({"ok": True})
