"""
Decoradores de seguridad para vistas de microservicios.

Proporciona decoradores para:
- Requerir comunicación cifrada
- Validar origen del microservicio
- Auditar accesos a datos sensibles
"""

import functools
import logging
from django.http import JsonResponse
from .crypto_service import crypto_service

logger = logging.getLogger(__name__)


def require_encrypted(func):
    """
    Decorador que requiere que el request venga cifrado.
    
    Uso:
        @require_encrypted
        def my_view(request):
            ...
    """
    @functools.wraps(func)
    def wrapper(request, *args, **kwargs):
        if not getattr(request, 'is_internal_service', False):
            # Request externo - permitir sin cifrado
            return func(request, *args, **kwargs)
        
        # Request interno - verificar cifrado
        if not hasattr(request, '_decrypted_body'):
            logger.warning(f"Request interno sin cifrar desde {request.source_service}")
            return JsonResponse(
                {'error': 'Se requiere comunicación cifrada'},
                status=400
            )
        
        return func(request, *args, **kwargs)
    
    return wrapper


def require_service(allowed_services: list):
    """
    Decorador que restringe acceso a ciertos microservicios.
    
    Uso:
        @require_service(['orders', 'clients'])
        def my_view(request):
            ...
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(request, *args, **kwargs):
            if not getattr(request, 'is_internal_service', False):
                # Request externo - permitir
                return func(request, *args, **kwargs)
            
            source = getattr(request, 'source_service', None)
            if source not in allowed_services:
                logger.warning(f"Acceso denegado a {source} - solo permitido: {allowed_services}")
                return JsonResponse(
                    {'error': 'Servicio no autorizado'},
                    status=403
                )
            
            return func(request, *args, **kwargs)
        
        return wrapper
    return decorator


def audit_access(entity_type: str):
    """
    Decorador para auditar accesos a datos sensibles.
    
    Uso:
        @audit_access('client')
        def get_client(request, client_id):
            ...
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(request, *args, **kwargs):
            # Obtener información del request
            source = getattr(request, 'source_service', 'external')
            user = getattr(request, 'user', None)
            user_info = str(user) if user and user.is_authenticated else 'anonymous'
            
            # Log de acceso
            logger.info(
                f"[AUDIT] Acceso a {entity_type} | "
                f"Source: {source} | "
                f"User: {user_info} | "
                f"Path: {request.path} | "
                f"Method: {request.method}"
            )
            
            return func(request, *args, **kwargs)
        
        return wrapper
    return decorator


def encrypt_response(entity_type: str):
    """
    Decorador que cifra automáticamente la respuesta si el request
    viene de otro microservicio.
    
    Uso:
        @encrypt_response('client')
        def get_client(request, client_id):
            return JsonResponse(client_data)
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(request, *args, **kwargs):
            response = func(request, *args, **kwargs)
            
            # Solo cifrar si es comunicación entre microservicios
            if not getattr(request, 'is_internal_service', False):
                return response
            
            # Solo cifrar JsonResponse
            if not isinstance(response, JsonResponse):
                return response
            
            try:
                # Obtener datos de la respuesta
                response_data = response.content.decode('utf-8')
                
                # Cifrar
                encrypted = crypto_service.create_secure_message(
                    data={'response': response_data},
                    source=entity_type,
                    destination=request.source_service
                )
                
                # Crear nueva respuesta cifrada
                encrypted_response = JsonResponse({'encrypted': encrypted})
                encrypted_response['X-Encrypted-Response'] = 'true'
                
                return encrypted_response
                
            except Exception as e:
                logger.error(f"Error cifrando respuesta: {str(e)}")
                return response
        
        return wrapper
    return decorator