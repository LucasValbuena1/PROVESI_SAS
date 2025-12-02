"""
Configuración de MongoDB usando MongoEngine.
"""

import mongoengine

def connect_mongodb():
    """Conecta a MongoDB."""
    mongoengine.connect(
        db='provesi_clients',
        host='localhost',
        port=27017,
        # Si requiere autenticación:
        # username='usuario',
        # password='password',
        # authentication_source='admin',
    )

def disconnect_mongodb():
    """Desconecta de MongoDB."""
    mongoengine.disconnect()