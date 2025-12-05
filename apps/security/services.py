"""
Servicios de seguridad para comunicación entre microservicios.

Provee acceso seguro a datos entre:
- Orders (PostgreSQL - provesi_orders)
- Clients (MongoDB - provesi_clients)
"""

import logging
from typing import Dict, List, Any, Optional

logger = logging.getLogger(__name__)


class SecureClientService:
    """
    Servicio para acceso seguro a datos de clientes desde otros microservicios.
    Clientes están en MongoDB.
    """
    
    def get_client_secure(self, client_id: str) -> Optional[Dict[str, Any]]:
        """
        Obtiene un cliente de forma segura.
        
        Args:
            client_id: ID del cliente (string ObjectId de MongoDB)
            
        Returns:
            Diccionario con datos del cliente o None si no existe
        """
        from apps.clients.models import Client
        from bson import ObjectId
        
        try:
            ObjectId(client_id)
        except:
            logger.warning(f"[SECURITY] ID de cliente inválido: {client_id}")
            return None
        
        try:
            client = Client.objects(id=client_id).first()
            if client:
                logger.info(f"[SECURITY] Cliente {client_id} obtenido de forma segura")
                return client.to_dict()
            return None
        except Exception as e:
            logger.error(f"[SECURITY] Error obteniendo cliente {client_id}: {str(e)}")
            return None
    
    def get_client_encrypted(self, client_id: str) -> Optional[str]:
        """Obtiene un cliente y retorna sus datos cifrados."""
        from .crypto_service import crypto_service
        
        client_data = self.get_client_secure(client_id)
        if client_data:
            import json
            return crypto_service.encrypt_aes(json.dumps(client_data))
        return None
    
    def get_clients_for_orders(self, client_ids: List[str]) -> Dict[str, Dict[str, Any]]:
        """
        Obtiene múltiples clientes para enriquecer órdenes.
        
        Args:
            client_ids: Lista de IDs de clientes (strings)
            
        Returns:
            Diccionario {client_id: client_data}
        """
        from apps.clients.models import Client
        from bson import ObjectId
        
        if not client_ids:
            return {}
        
        valid_ids = []
        for cid in client_ids:
            try:
                ObjectId(cid)
                valid_ids.append(cid)
            except:
                pass
        
        if not valid_ids:
            return {}
        
        try:
            clients = Client.objects(id__in=valid_ids)
            result = {str(c.id): c.to_dict() for c in clients}
            logger.info(f"[SECURITY] {len(result)} clientes obtenidos para órdenes")
            return result
        except Exception as e:
            logger.error(f"[SECURITY] Error obteniendo clientes: {str(e)}")
            return {}


class SecureOrderService:
    """
    Servicio para acceso seguro a datos de órdenes desde otros microservicios.
    Órdenes están en PostgreSQL.
    """
    
    def get_orders_for_client(self, client_id: str) -> List[Dict[str, Any]]:
        """
        Obtiene las órdenes de un cliente de forma segura.
        
        Args:
            client_id: ID del cliente (string para compatibilidad con MongoDB)
            
        Returns:
            Lista de diccionarios con datos de órdenes
        """
        from apps.orders.models import Order
        
        try:
            orders = Order.objects.filter(client_id=client_id)
            result = []
            for order in orders:
                result.append({
                    'id': order.id,
                    'order_number': order.order_number,
                    'status': order.status,
                    'status_display': order.get_status_display(),
                    'created_at': order.created_at.isoformat() if order.created_at else None,
                    'updated_at': order.updated_at.isoformat() if order.updated_at else None,
                })
            logger.info(f"[SECURITY] {len(result)} órdenes obtenidas para cliente {client_id}")
            return result
        except Exception as e:
            logger.error(f"[SECURITY] Error obteniendo órdenes para cliente {client_id}: {str(e)}")
            return []
    
    def get_orders_count_for_clients(self, client_ids: List[str]) -> Dict[str, int]:
        """
        Obtiene el conteo de órdenes para múltiples clientes.
        
        Args:
            client_ids: Lista de IDs de clientes (strings)
            
        Returns:
            Diccionario {client_id: count}
        """
        from apps.orders.models import Order
        from django.db.models import Count
        
        if not client_ids:
            return {}
        
        try:
            counts = (
                Order.objects
                .filter(client_id__in=client_ids)
                .values('client_id')
                .annotate(count=Count('id'))
            )
            result = {str(item['client_id']): item['count'] for item in counts}
            logger.info(f"[SECURITY] Conteo de órdenes obtenido para {len(client_ids)} clientes")
            return result
        except Exception as e:
            logger.error(f"[SECURITY] Error contando órdenes: {str(e)}")
            return {}


class SecureDataService:
    """Servicio para cifrar/descifrar datos sensibles."""
    
    SENSITIVE_FIELDS = {
        'client': ['email', 'phone', 'address', 'name'],
        'order': ['client_id']
    }
    
    def encrypt_sensitive_fields(self, data: Dict[str, Any], entity_type: str) -> Dict[str, Any]:
        """Cifra campos sensibles de una entidad."""
        from .crypto_service import crypto_service
        
        if entity_type not in self.SENSITIVE_FIELDS:
            return data
        
        result = data.copy()
        for field in self.SENSITIVE_FIELDS[entity_type]:
            if field in result and result[field]:
                result[field] = crypto_service.encrypt_aes(str(result[field]))
        
        return result
    
    def decrypt_sensitive_fields(self, data: Dict[str, Any], entity_type: str) -> Dict[str, Any]:
        """Descifra campos sensibles de una entidad."""
        from .crypto_service import crypto_service
        
        if entity_type not in self.SENSITIVE_FIELDS:
            return data
        
        result = data.copy()
        for field in self.SENSITIVE_FIELDS[entity_type]:
            if field in result and result[field]:
                try:
                    result[field] = crypto_service.decrypt_aes(result[field])
                except:
                    pass
        
        return result


# Instancias globales
secure_client_service = SecureClientService()
secure_order_service = SecureOrderService()
secure_data_service = SecureDataService()