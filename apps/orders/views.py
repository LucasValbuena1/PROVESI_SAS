from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.cache import cache_page
from django.core.cache import cache
from rest_framework.decorators import api_view
from .models import Order

# TTL de caché (segundos) para las pruebas de disponibilidad
CACHE_TTL_SECONDS = 300


def order_lookup(request):
    """
    Página HTML simple para buscar órdenes por número.
    (No cacheada; se usa principalmente para UI manual.)
    """
    q = request.GET.get("q", "").strip()
    order, not_found = None, False
    if q:
        order = (
            Order.objects.only("order_number", "status", "updated_at")
            .filter(order_number__iexact=q)
            .first()
        )
        if not order:
            not_found = True
    return render(
        request,
        "orders/lookup.html",
        {"query": q, "order": order, "not_found": not_found},
    )


@api_view(["GET"])
def order_status(request, order_number: str):
    """
    API por orden con estrategia 'stale-if-error':
      - Intenta leer desde DB.
      - Si DB falla, devuelve el último valor cacheado (si existe).
      - Si no hay caché previo, responde 503.
    Clave de caché: order:status:{order_number}
    """
    cache_key = f"order:status:{order_number}"
    try:
        order = get_object_or_404(
            Order.objects.only("order_number", "status", "updated_at"),
            order_number=order_number,
        )
        payload = {
            "order_number": order.order_number,
            "status": order.status,
            "last_updated": order.updated_at.isoformat(),
        }
        cache.set(cache_key, payload, CACHE_TTL_SECONDS)
        return JsonResponse({"from_cache": False, "data": payload})
    except Exception:
        cached = cache.get(cache_key)
        if cached is None:
            return JsonResponse({"error": "db_down_and_no_cache"}, status=503)
        return JsonResponse({"from_cache": True, "data": cached})


def health(request):
    """
    Health básico sin caché.
    """
    return JsonResponse({"ok": True})


@cache_page(CACHE_TTL_SECONDS)
def health_cached(request):
    """
    Health cacheado: útil para demostrar respuestas 200 durante el TTL
    aun cuando la DB esté caída.
    """
    return JsonResponse({"ok": True, "cached_ttl_s": CACHE_TTL_SECONDS})


@api_view(["GET"])
def orders_summary(request):
    """
    Resumen de órdenes con 'stale-if-error':
      - Cuenta total de órdenes.
      - Si falla DB, devuelve el último valor cacheado.
    Clave: orders:summary:v1
    """
    cache_key = "orders:summary:v1"
    try:
        total = Order.objects.count()
        payload = {"orders_total": total}
        cache.set(cache_key, payload, CACHE_TTL_SECONDS)
        return JsonResponse({"from_cache": False, "data": payload})
    except Exception:
        cached = cache.get(cache_key)
        if cached is None:
            return JsonResponse({"error": "db_down_and_no_cache"}, status=503)
        return JsonResponse({"from_cache": True, "data": cached})
