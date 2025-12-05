"""API FastAPI para el microservicio de Clientes (MongoDB)."""

from fastapi import APIRouter, HTTPException
from bson import ObjectId
from .models import Client
from .schemas import ClientCreate, ClientUpdate
from apps.security.services import secure_order_service

router = APIRouter(prefix="/api/clients", tags=["Clientes"])


def validate_object_id(client_id: str) -> bool:
    """Valida que el ID sea un ObjectId válido de MongoDB."""
    try:
        ObjectId(client_id)
        return True
    except:
        return False


@router.get("/")
def list_clients():
    """Lista todos los clientes."""
    clients = Client.objects.all()
    
    # Obtener conteo de órdenes (usando string IDs)
    client_ids = [str(c.id) for c in clients]
    orders_counts = secure_order_service.get_orders_count_for_clients(client_ids)
    
    data = []
    for client in clients:
        client_data = client.to_dict()
        client_data["orders_count"] = orders_counts.get(str(client.id), 0)
        data.append(client_data)
    
    return {"status": "success", "data": data}


@router.post("/", status_code=201)
def create_client(client: ClientCreate):
    """Crea un nuevo cliente."""
    # Verificar email único
    if Client.objects(email=client.email).first():
        raise HTTPException(status_code=400, detail="El email ya existe")
    
    new_client = Client(
        name=client.name,
        email=client.email,
        phone=client.phone or "",
        address=client.address or ""
    )
    new_client.save()
    
    return {"status": "success", "data": new_client.to_dict()}


@router.get("/{client_id}")
def get_client(client_id: str):
    """Obtiene un cliente por ID."""
    if not validate_object_id(client_id):
        raise HTTPException(status_code=400, detail="ID de cliente inválido")
    
    client = Client.objects(id=client_id).first()
    if not client:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")
    
    client_data = client.to_dict()
    
    # Agregar órdenes del cliente
    orders = secure_order_service.get_orders_for_client(client_id)
    client_data["orders"] = orders
    
    return {"status": "success", "data": client_data}


@router.put("/{client_id}")
def update_client(client_id: str, client_data: ClientUpdate):
    """Actualiza un cliente."""
    if not validate_object_id(client_id):
        raise HTTPException(status_code=400, detail="ID de cliente inválido")
    
    client = Client.objects(id=client_id).first()
    if not client:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")
    
    if client_data.name is not None:
        client.name = client_data.name
    
    if client_data.email is not None:
        # Verificar email único
        existing = Client.objects(email=client_data.email, id__ne=client_id).first()
        if existing:
            raise HTTPException(status_code=400, detail="El email ya existe")
        client.email = client_data.email
    
    if client_data.phone is not None:
        client.phone = client_data.phone
    
    if client_data.address is not None:
        client.address = client_data.address
    
    client.save()
    
    return {"status": "success", "data": client.to_dict()}


@router.delete("/{client_id}")
def delete_client(client_id: str):
    """Elimina un cliente."""
    if not validate_object_id(client_id):
        raise HTTPException(status_code=400, detail="ID de cliente inválido")
    
    client = Client.objects(id=client_id).first()
    if not client:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")
    
    # Desasociar órdenes
    from apps.orders.models import Order
    Order.objects.filter(client_id=client_id).update(client_id=None)
    
    client.delete()
    return {"status": "success", "message": "Cliente eliminado"}


@router.get("/health/status")
def health():
    """Health check del microservicio de clientes."""
    try:
        Client.objects.first()
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"
    
    return {
        "service": "clients",
        "status": "ok" if db_status == "connected" else "error",
        "database": "MongoDB",
        "connection": db_status
    }