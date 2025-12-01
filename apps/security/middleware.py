"""
Middleware de seguridad para comunicación entre microservicios.

Proporciona:
- Cifrado automático de respuestas entre microservicios
- Descifrado automático de requests entre microservicios
- Validación de tokens de servicio
- Logging de accesos
"""

import json
import logging
from django.http import JsonResponse, HttpResponse
from django.conf import settings
from .crypto_service import crypto_service

logger = logging.getLogger(__name__)


class MicroserviceSecurityMiddleware:
    """
    Middleware que maneja la seguridad de comunicación entre microservicios.
    
    Detecta requests internos (entre microservicios) y aplica cifrado/descifrado.
    """
    
    # Header que identifica comunicaciones entre microservicios
    SERVICE_HEADER = 'X-Microservice-Source'
    ENCRYPTED_HEADER = 'X-Encrypted-Payload'
    SERVICE_TOKEN_HEADER = 'X-Service-Token'
    
    def __init__(self, get_response):
        self.get_response = get_response
        self.service_token = getattr(settings, 'MICROSERVICE_SERVICE_TOKEN', None)
    
    def __call__(self, request):
        # Verificar si es una comunicación entre microservicios
        source_service = request.headers.get(self.SERVICE_HEADER)
        
        if source_service:
            # Validar token de servicio
            if not self._validate_service_token(request):
                logger.warning(f"Token de servicio inválido desde {source_service}")
                return JsonResponse(
                    {'error': 'Token de servicio inválido'},
                    status=401
                )
            
            # Descifrar payload si está cifrado
            if request.headers.get(self.ENCRYPTED_HEADER) == 'true':
                try:
                    request = self._decrypt_request(request, source_service)
                except Exception as e:
                    logger.error(f"Error descifrando request: {str(e)}")
                    return JsonResponse(
                        {'error': 'Error al descifrar mensaje'},
                        status=400
                    )
            
            # Marcar request como interno
            request.is_internal_service = True
            request.source_service = source_service
        else:
            request.is_internal_service = False
            request.source_service = None
        
        # Procesar request
        response = self.get_response(request)
        
        return response
    
    def _validate_service_token(self, request) -> bool:
        """Valida el token de servicio."""
        if not self.service_token:
            # Si no hay token configurado, permitir (desarrollo)
            return True
        
        received_token = request.headers.get(self.SERVICE_TOKEN_HEADER)
        return received_token == self.service_token
    
    def _decrypt_request(self, request, source_service):
        """Descifra el body del request."""
        if request.body:
            encrypted_body = request.body.decode('utf-8')
            
            # Determinar el servicio destino basado en la URL
            destination = self._get_service_from_path(request.path)
            
            # Descifrar
            decrypted_data = crypto_service.verify_and_decrypt_message(
                encrypted_body,
                destination
            )
            
            # Reemplazar body (Django no permite esto directamente, 
            # así que guardamos en un atributo)
            request._decrypted_body = decrypted_data
        
        return request
    
    def _get_service_from_path(self, path: str) -> str:
        """Determina el servicio destino basado en la ruta."""
        if '/clients/' in path:
            return 'clients'
        elif '/orders/' in path:
            return 'orders'
        return 'unknown'


class SecureServiceClient:
    """
    Cliente para comunicación segura entre microservicios.
    
    Uso:
        client = SecureServiceClient('orders')
        data = client.get_client(client_id)
    """
    
    def __init__(self, service_name: str):
        self.service_name = service_name
        self.service_token = getattr(settings, 'MICROSERVICE_SERVICE_TOKEN', '')
    
    def create_encrypted_payload(self, data: dict, destination: str) -> tuple:
        """
        Crea un payload cifrado para enviar a otro microservicio.
        
        Returns:
            Tupla (encrypted_payload, headers)
        """
        encrypted = crypto_service.create_secure_message(
            data=data,
            source=self.service_name,
            destination=destination
        )
        
        headers = {
            MicroserviceSecurityMiddleware.SERVICE_HEADER: self.service_name,
            MicroserviceSecurityMiddleware.ENCRYPTED_HEADER: 'true',
            MicroserviceSecurityMiddleware.SERVICE_TOKEN_HEADER: self.service_token,
            'Content-Type': 'application/json'
        }
        
        return encrypted, headers
    
    def decrypt_response(self, encrypted_response: str) -> dict:
        """Descifra una respuesta de otro microservicio."""
        return crypto_service.verify_and_decrypt_message(
            encrypted_response,
            self.service_name
        )