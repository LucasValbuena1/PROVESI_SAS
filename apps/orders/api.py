"""API FastAPI para el microservicio de Órdenes (PostgreSQL + MongoDB clients)."""

import re
from fastapi import APIRouter, HTTPException
from django.utils import timezone
from .models import Order, OrderStatus as DjangoOrderStatus
from .schemas import OrderCreate, OrderUpdate, OrderStatus
from apps.security.services import secure_client_service

router = APIRouter(prefix="/api/orders", tags=["Órdenes"])


def order_to_dict(order: Order) -> dict:
    """Convierte una orden a diccionario."""
    data = {
        "id": order.id,
        "order_number": order.order_number,
        "client_id": order.client_id,
        "status": order.status,
        "status_display": order.get_status_display(),
        "created_at": order.created_at,
        "updated_at": order.updated_at,
    }
    if order.status == 'returned':
        data["return_reason"] = order.return_reason
        data["returned_at"] = order.returned_at
    return data


@router.get("/")
def list_orders():
    """Lista todas las órdenes."""
    orders = Order.objects.using('orders_db').all()
    
    # Obtener client_ids únicos (ahora son strings)
    client_ids = list(set(o.client_id for o in orders if o.client_id))
    clients_map = secure_client_service.get_clients_for_orders(client_ids)
    
    data = []
    for order in orders:
        order_data = order_to_dict(order)
        if order.client_id and order.client_id in clients_map:
            order_data["client"] = clients_map[order.client_id]
        data.append(order_data)
    
    return {"status": "success", "data": data}


@router.post("/", status_code=201)
def create_order(order: OrderCreate):
    """Crea una nueva orden."""
    # Validar formato
    if not re.match(r"^[A-Za-z0-9\-]+$", order.order_number):
        raise HTTPException(status_code=400, detail="El código solo puede contener letras, números y guiones")
    
    if Order.objects.using('orders_db').filter(order_number__iexact=order.order_number).exists():
        raise HTTPException(status_code=400, detail="El número de orden ya existe")
    
    # Validar cliente (ahora es string ID de MongoDB)
    client_id = None
    if order.client_id:
        client = secure_client_service.get_client_secure(order.client_id)
        if not client:
            raise HTTPException(status_code=400, detail="Cliente no encontrado")
        client_id = order.client_id
    
    new_order = Order(
        order_number=order.order_number,
        client_id=client_id,
        status=order.status.value
    )
    new_order.save(using='orders_db')
    
    return {"status": "success", "data": order_to_dict(new_order)}


@router.get("/returns")
def list_returns():
    """Lista todas las órdenes devueltas."""
    orders = Order.objects.using('orders_db').filter(
        status=DjangoOrderStatus.RETURNED
    ).order_by('-returned_at', '-updated_at')
    
    # Obtener clientes
    client_ids = list(set(o.client_id for o in orders if o.client_id))
    clients_map = secure_client_service.get_clients_for_orders(client_ids)
    
    data = []
    for order in orders:
        order_data = order_to_dict(order)
        if order.client_id and order.client_id in clients_map:
            order_data["client"] = clients_map[order.client_id]
        data.append(order_data)
    
    return {"status": "success", "total": len(data), "data": data}


@router.get("/{order_number}")
def get_order(order_number: str):
    """Obtiene una orden por número."""
    try:
        order = Order.objects.using('orders_db').get(order_number=order_number)
        order_data = order_to_dict(order)
        
        if order.client_id:
            client = secure_client_service.get_client_secure(order.client_id)
            if client:
                order_data["client"] = client
        
        return {"status": "success", "data": order_data}
    except Order.DoesNotExist:
        raise HTTPException(status_code=404, detail="Orden no encontrada")


@router.put("/{order_number}")
def update_order(order_number: str, order_data: OrderUpdate):
    """Actualiza una orden."""
    try:
        order = Order.objects.using('orders_db').get(order_number=order_number)
        
        if order_data.order_number is not None:
            if not re.match(r"^[A-Za-z0-9\-]+$", order_data.order_number):
                raise HTTPException(status_code=400, detail="El código solo puede contener letras, números y guiones")
            if order_data.order_number.lower() != order.order_number.lower():
                if Order.objects.using('orders_db').filter(order_number__iexact=order_data.order_number).exists():
                    raise HTTPException(status_code=400, detail="El número de orden ya existe")
            order.order_number = order_data.order_number
        
        if order_data.status is not None:
            # Si cambia a devuelto, requiere razón
            if order_data.status == OrderStatus.returned:
                if not order_data.return_reason:
                    raise HTTPException(status_code=400, detail="return_reason es requerido para estado devuelto")
                order.return_reason = order_data.return_reason
                order.returned_at = timezone.now()
            order.status = order_data.status.value
        
        if order_data.client_id is not None:
            if order_data.client_id:
                client = secure_client_service.get_client_secure(order_data.client_id)
                if not client:
                    raise HTTPException(status_code=400, detail="Cliente no encontrado")
                order.client_id = order_data.client_id
            else:
                order.client_id = None
        
        order.save(using='orders_db')
        
        return {"status": "success", "data": order_to_dict(order)}
        
    except Order.DoesNotExist:
        raise HTTPException(status_code=404, detail="Orden no encontrada")


@router.delete("/{order_number}")
def delete_order(order_number: str):
    """Elimina una orden."""
    try:
        order = Order.objects.using('orders_db').get(order_number=order_number)
        order.delete(using='orders_db')
        return {"status": "success", "message": "Orden eliminada"}
    except Order.DoesNotExist:
        raise HTTPException(status_code=404, detail="Orden no encontrada")


@router.get("/health/status")
def health():
    """Health check del microservicio de órdenes."""
    try:
        Order.objects.using('orders_db').first()
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"
    
    return {
        "service": "orders",
        "status": "ok" if db_status == "connected" else "error",
        "database": "PostgreSQL",
        "connection": db_status
    }