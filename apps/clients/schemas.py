"""Schemas Pydantic para el microservicio de Clientes."""

from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime


class ClientCreate(BaseModel):
    name: str
    email: EmailStr
    phone: Optional[str] = ""
    address: Optional[str] = ""


class ClientUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address: Optional[str] = None


class ClientResponse(BaseModel):
    id: str  # MongoDB usa string IDs
    name: str
    email: str
    phone: str
    address: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ClientListResponse(BaseModel):
    status: str
    data: list[ClientResponse]


class ClientDetailResponse(BaseModel):
    status: str
    data: ClientResponse