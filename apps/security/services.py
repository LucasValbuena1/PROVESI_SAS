"""
Servicio de comunicación segura entre microservicios.

Este módulo proporciona funciones de alto nivel para que los microservicios
se comuniquen de forma segura, cifrando los datos sensibles.
"""

import json
import logging
from typing import Optional, List, Dict, Any
from django.conf import settings
from .crypto_service import crypto_service

logger = logging.getLogger(__name__)


class SecureDataService:
    """
    Servicio para cifrar/descifrar datos sensibles en la comunicación
    entre microservicios.
    """
    
    # Campos sensibles que siempre deben cifrarse
    SENSITIVE_FIELDS = {
        'client': ['email', 'phone', 'address', 'name'],
        'order': ['client_id']
    }
    
    def __init__(self):
        self.crypto = crypto_service
    
    def encrypt_sensitive_fields(self, data: dict, entity_type: str) -> dict:
        """
        Cifra los campos sensibles de un diccionario.
        
        Args:
            data: Diccionario con los datos
            entity_type: Tipo de entidad ('client', 'order')
            
        Returns:
            Diccionario con campos sensibles cifrados
        """
        if entity_type not in self.SENSITIVE_FIELDS:
            return data
        
        encrypted_data = data.copy()
        sensitive = self.SENSITIVE_FIELDS[entity_type]
        
        for field in sensitive:
            if field in encrypted_data and encrypted_data[field] is not None:
                # Convertir a string si no lo es
                value = str(encrypted_data[field])
                encrypted_data[field] = self.crypto.encrypt_aes(value)
                encrypted_data[f'{field}_encrypted'] = True
        
        return encrypted_data
    
    def decrypt_sensitive_fields(self, data: dict, entity_type: str) -> dict:
        """
        Descifra los campos sensibles de un diccionario.
        
        Args:
            data: Diccionario con datos cifrados
            entity_type: Tipo de entidad ('client', 'order')
            
        Returns:
            Diccionario con campos descifrados
        """
        if entity_type not in self.SENSITIVE_FIELDS:
            return data
        
        decrypted_data = data.copy()
        sensitive = self.SENSITIVE_FIELDS[entity_type]
        
        for field in sensitive:
            if data.get(f'{field}_encrypted') and field in data:
                try:
                    decrypted_data[field] = self.crypto.decrypt_aes(data[field])
                    del decrypted_data[f'{field}_encrypted']
                except Exception as e:
                    logger.error(f"Error descifrando campo {field}: {str(e)}")
                    decrypted_data[field] = None
        
        return decrypted_data


class SecureClientService:
    """
    Servicio para acceder a datos de clientes de forma segura
    desde el microservicio de órdenes.
    """
    
    def __init__(self):
        self.data_service = SecureDataService()
    
    def get_client_secure(self, client_id: int) -> Optional[Dict[str, Any]]:
        """
        Obtiene un cliente de forma segura desde la base de datos de clientes.
        
        Args:
            client_id: ID del cliente
            
        Returns:
            Diccionario con datos del cliente o None
        """
        from apps.clients.models import Client
        
        try:
            client = Client.objects.using('clients_db').get(id=client_id)
            
            # Crear diccionario con datos
            client_data = {
                'id': client.id,
                'name': client.name,
                'email': client.email,
                'phone': client.phone,
                'address': client.address,
            }
            
            logger.info(f"[SECURITY] Cliente {client_id} obtenido de forma segura")
            return client_data
            
        except Client.DoesNotExist:
            logger.warning(f"[SECURITY] Cliente {client_id} no encontrado")
            return None
        except Exception as e:
            logger.error(f"[SECURITY] Error obteniendo cliente {client_id}: {str(e)}")
            return None
    
    def get_client_encrypted(self, client_id: int) -> Optional[Dict[str, Any]]:
        """
        Obtiene un cliente con sus datos sensibles cifrados.
        
        Args:
            client_id: ID del cliente
            
        Returns:
            Diccionario con datos sensibles cifrados
        """
        client_data = self.get_client_secure(client_id)
        
        if client_data:
            return self.data_service.encrypt_sensitive_fields(client_data, 'client')
        
        return None
    
    def get_clients_for_orders(self, client_ids: List[int]) -> Dict[int, Dict[str, Any]]:
        """
        Obtiene múltiples clientes de forma optimizada y segura.
        
        Args:
            client_ids: Lista de IDs de clientes
            
        Returns:
            Diccionario {client_id: client_data}
        """
        from apps.clients.models import Client
        
        if not client_ids:
            return {}
        
        try:
            clients = Client.objects.using('clients_db').filter(id__in=client_ids)
            
            result = {}
            for client in clients:
                result[client.id] = {
                    'id': client.id,
                    'name': client.name,
                    'email': client.email,
                    'phone': client.phone,
                    'address': client.address,
                }
            
            logger.info(f"[SECURITY] {len(result)} clientes obtenidos de forma segura")
            return result
            
        except Exception as e:
            logger.error(f"[SECURITY] Error obteniendo clientes: {str(e)}")
            return {}


class SecureOrderService:
    """
    Servicio para acceder a datos de órdenes de forma segura
    desde el microservicio de clientes.
    """
    
    def __init__(self):
        self.data_service = SecureDataService()
    
    def get_orders_for_client(self, client_id: int) -> List[Dict[str, Any]]:
        """
        Obtiene las órdenes de un cliente de forma segura.
        
        Args:
            client_id: ID del cliente
            
        Returns:
            Lista de diccionarios con datos de órdenes
        """
        from apps.orders.models import Order
        
        try:
            orders = Order.objects.using('orders_db').filter(client_id=client_id)
            
            result = []
            for order in orders:
                result.append({
                    'id': order.id,
                    'order_number': order.order_number,
                    'status': order.status,
                    'status_display': order.get_status_display(),
                    'client_id': order.client_id,
                    'updated_at': order.updated_at.isoformat(),
                })
            
            logger.info(f"[SECURITY] {len(result)} órdenes obtenidas para cliente {client_id}")
            return result
            
        except Exception as e:
            logger.error(f"[SECURITY] Error obteniendo órdenes para cliente {client_id}: {str(e)}")
            return []
    
    def get_orders_count_for_clients(self, client_ids: List[int]) -> Dict[int, int]:
        """
        Obtiene el conteo de órdenes para múltiples clientes.
        
        Args:
            client_ids: Lista de IDs de clientes
            
        Returns:
            Diccionario {client_id: orders_count}
        """
        from apps.orders.models import Order
        from django.db.models import Count
        
        if not client_ids:
            return {}
        
        try:
            counts = (
                Order.objects.using('orders_db')
                .filter(client_id__in=client_ids)
                .values('client_id')
                .annotate(count=Count('id'))
            )
            
            result = {item['client_id']: item['count'] for item in counts}
            
            logger.info(f"[SECURITY] Conteo de órdenes obtenido para {len(client_ids)} clientes")
            return result
            
        except Exception as e:
            logger.error(f"[SECURITY] Error obteniendo conteo de órdenes: {str(e)}")
            return {}


# Instancias globales de los servicios
secure_data_service = SecureDataService()
secure_client_service = SecureClientService()
secure_order_service = SecureOrderService()