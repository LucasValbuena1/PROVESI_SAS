"""Schemas Pydantic para el microservicio de Órdenes."""

from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from enum import Enum


class OrderStatus(str, Enum):
    received = "received"
    picking = "picking"
    packing = "packing"
    shipped = "shipped"
    delivered = "delivered"
    returned = "returned"
    cancelled = "cancelled"


class OrderCreate(BaseModel):
    order_number: str
    client_id: Optional[str] = None  # String para MongoDB ObjectId
    status: Optional[OrderStatus] = OrderStatus.received


class OrderUpdate(BaseModel):
    order_number: Optional[str] = None
    client_id: Optional[str] = None  # String para MongoDB ObjectId
    status: Optional[OrderStatus] = None
    return_reason: Optional[str] = None


class OrderResponse(BaseModel):
    id: int
    order_number: str
    client_id: Optional[str]  # String para MongoDB ObjectId
    status: str
    status_display: str
    return_reason: Optional[str] = None
    returned_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True