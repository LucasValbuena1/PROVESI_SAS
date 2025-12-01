"""
Servicio de Cifrado para comunicación entre microservicios.

Implementa:
- AES-256 para cifrado simétrico de datos
- HMAC para verificación de integridad
- Timestamps para prevenir ataques de replay

Las claves están predefinidas para facilitar el desarrollo.
En producción, se recomienda usar variables de entorno.
"""

import os
import json
import base64
import hashlib
import hmac
from datetime import datetime, timedelta
from typing import Dict, Any

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend


class CryptoService:
    """
    Servicio principal de criptografía para comunicación segura entre microservicios.
    """
    
    # Claves predefinidas (32 bytes cada una para AES-256)
    # En producción, cambiar estas claves y usar variables de entorno
    DEFAULT_AES_KEY = b'PROVESI_SAS_AES_KEY_32_BYTES!!'  # Exactamente 32 bytes
    DEFAULT_HMAC_KEY = b'PROVESI_SAS_HMAC_KEY_32_BYTES!!'  # Exactamente 32 bytes
    
    # Tiempo máximo de validez de un mensaje (5 minutos)
    MESSAGE_VALIDITY_SECONDS = 300
    
    def __init__(self):
        """Inicializa el servicio con las claves predefinidas."""
        self.aes_key = self._get_aes_key()
        self.hmac_key = self._get_hmac_key()
    
    def _get_aes_key(self) -> bytes:
        """Obtiene la clave AES."""
        # Intentar obtener de variable de entorno, si no usar la predefinida
        env_key = os.environ.get('MICROSERVICE_AES_KEY')
        if env_key:
            try:
                return base64.b64decode(env_key)
            except Exception:
                pass
        return self.DEFAULT_AES_KEY
    
    def _get_hmac_key(self) -> bytes:
        """Obtiene la clave HMAC."""
        env_key = os.environ.get('MICROSERVICE_HMAC_KEY')
        if env_key:
            try:
                return base64.b64decode(env_key)
            except Exception:
                pass
        return self.DEFAULT_HMAC_KEY
    
    # ==================
    # CIFRADO AES-256
    # ==================
    
    def encrypt_aes(self, plaintext: str) -> str:
        """
        Cifra datos usando AES-256-CBC.
        
        Args:
            plaintext: Texto plano a cifrar
            
        Returns:
            String en base64 con formato: iv:ciphertext:hmac
        """
        # Generar IV aleatorio (16 bytes)
        iv = os.urandom(16)
        
        # Preparar el cifrador
        cipher = Cipher(
            algorithms.AES(self.aes_key),
            modes.CBC(iv),
            backend=default_backend()
        )
        encryptor = cipher.encryptor()
        
        # Aplicar padding PKCS7
        padder = padding.PKCS7(128).padder()
        padded_data = padder.update(plaintext.encode('utf-8')) + padder.finalize()
        
        # Cifrar
        ciphertext = encryptor.update(padded_data) + encryptor.finalize()
        
        # Generar HMAC para integridad
        mac = hmac.new(
            self.hmac_key,
            iv + ciphertext,
            hashlib.sha256
        ).digest()
        
        # Codificar en base64 y combinar
        result = f"{base64.b64encode(iv).decode()}:{base64.b64encode(ciphertext).decode()}:{base64.b64encode(mac).decode()}"
        
        return result
    
    def decrypt_aes(self, encrypted_data: str) -> str:
        """
        Descifra datos cifrados con AES-256-CBC.
        
        Args:
            encrypted_data: String en formato iv:ciphertext:hmac
            
        Returns:
            Texto plano descifrado
            
        Raises:
            ValueError: Si el HMAC no coincide o el formato es inválido
        """
        try:
            # Separar componentes
            parts = encrypted_data.split(':')
            if len(parts) != 3:
                raise ValueError("Formato de datos cifrados inválido")
            
            iv = base64.b64decode(parts[0])
            ciphertext = base64.b64decode(parts[1])
            received_mac = base64.b64decode(parts[2])
            
            # Verificar HMAC
            expected_mac = hmac.new(
                self.hmac_key,
                iv + ciphertext,
                hashlib.sha256
            ).digest()
            
            if not hmac.compare_digest(received_mac, expected_mac):
                raise ValueError("HMAC inválido - datos posiblemente manipulados")
            
            # Descifrar
            cipher = Cipher(
                algorithms.AES(self.aes_key),
                modes.CBC(iv),
                backend=default_backend()
            )
            decryptor = cipher.decryptor()
            padded_plaintext = decryptor.update(ciphertext) + decryptor.finalize()
            
            # Quitar padding
            unpadder = padding.PKCS7(128).unpadder()
            plaintext = unpadder.update(padded_plaintext) + unpadder.finalize()
            
            return plaintext.decode('utf-8')
            
        except Exception as e:
            raise ValueError(f"Error al descifrar: {str(e)}")
    
    # ==================
    # MENSAJES SEGUROS
    # ==================
    
    def create_secure_message(self, data: Dict[str, Any], source: str, destination: str) -> str:
        """
        Crea un mensaje seguro con timestamp y firma.
        
        Args:
            data: Diccionario con los datos a enviar
            source: Identificador del microservicio origen
            destination: Identificador del microservicio destino
            
        Returns:
            Mensaje cifrado listo para enviar
        """
        message = {
            'data': data,
            'source': source,
            'destination': destination,
            'timestamp': datetime.utcnow().isoformat(),
            'nonce': base64.b64encode(os.urandom(16)).decode()
        }
        
        # Convertir a JSON y cifrar
        json_message = json.dumps(message, default=str)
        encrypted = self.encrypt_aes(json_message)
        
        return encrypted
    
    def verify_and_decrypt_message(
        self, 
        encrypted_message: str, 
        expected_destination: str
    ) -> Dict[str, Any]:
        """
        Verifica y descifra un mensaje seguro.
        
        Args:
            encrypted_message: Mensaje cifrado
            expected_destination: Destino esperado del mensaje
            
        Returns:
            Diccionario con los datos del mensaje
            
        Raises:
            ValueError: Si el mensaje es inválido, expirado o el destino no coincide
        """
        # Descifrar
        decrypted = self.decrypt_aes(encrypted_message)
        message = json.loads(decrypted)
        
        # Verificar destino
        if message.get('destination') != expected_destination:
            raise ValueError("Destino del mensaje no coincide")
        
        # Verificar timestamp (prevenir replay attacks)
        timestamp = datetime.fromisoformat(message['timestamp'])
        age = datetime.utcnow() - timestamp
        
        if age > timedelta(seconds=self.MESSAGE_VALIDITY_SECONDS):
            raise ValueError("Mensaje expirado")
        
        if age < timedelta(seconds=-30):  # Permitir 30 segundos de desincronización
            raise ValueError("Timestamp del mensaje es del futuro")
        
        return message['data']


# Instancia global del servicio
crypto_service = CryptoService()