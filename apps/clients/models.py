"""
Modelo de Cliente usando MongoDB (MongoEngine).
"""

from mongoengine import Document, StringField, EmailField, DateTimeField
from datetime import datetime


class Client(Document):
    """Modelo de Cliente almacenado en MongoDB."""
    
    name = StringField(required=True, max_length=100)
    email = EmailField(required=True, unique=True)
    phone = StringField(max_length=20, default="")
    address = StringField(default="")
    created_at = DateTimeField(default=datetime.utcnow)
    updated_at = DateTimeField(default=datetime.utcnow)
    
    meta = {
        'collection': 'clients',
        'ordering': ['name'],
        'indexes': ['email', 'name']
    }
    
    def save(self, *args, **kwargs):
        self.updated_at = datetime.utcnow()
        return super().save(*args, **kwargs)
    
    def to_dict(self):
        return {
            'id': str(self.id),
            'name': self.name,
            'email': self.email,
            'phone': self.phone,
            'address': self.address,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }
    
    def __str__(self):
        return self.name