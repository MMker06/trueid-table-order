import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Integer, ForeignKey, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from ..core.database import Base
import enum


class OrderStatus(str, enum.Enum):
    PENDING_VERIFY = "pending_verify"
    CONFIRMED = "confirmed"
    PREPARING = "preparing"
    READY = "ready"
    DONE = "done"
    CANCELLED = "cancelled"


class TableOrder(Base):
    __tablename__ = "table_orders"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    merchant_id = Column(UUID(as_uuid=True), ForeignKey("merchants.id"), nullable=False)
    table_number = Column(String(10), nullable=False)
    status = Column(SAEnum(OrderStatus), default=OrderStatus.CONFIRMED, nullable=False)
    total_amount = Column(Integer, nullable=False, default=0)
    requires_adult_verify = Column(Boolean, default=False)
    adult_verify_count = Column(Integer, default=0)
    adult_verified_count = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    merchant = relationship("Merchant", back_populates="orders")
    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")
    verifications = relationship("OrderVerification", back_populates="order", cascade="all, delete-orphan")
    mobile_tokens = relationship("MobileVerifyToken", back_populates="order", cascade="all, delete-orphan")


class OrderItem(Base):
    __tablename__ = "order_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    order_id = Column(UUID(as_uuid=True), ForeignKey("table_orders.id"), nullable=False)
    menu_item_id = Column(UUID(as_uuid=True), nullable=True)
    name = Column(String(100), nullable=False)
    price = Column(Integer, nullable=False)
    quantity = Column(Integer, nullable=False, default=1)
    is_adult_only = Column(Boolean, default=False)

    order = relationship("TableOrder", back_populates="items")


class OrderVerification(Base):
    __tablename__ = "order_verifications"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    order_id = Column(UUID(as_uuid=True), ForeignKey("table_orders.id"), nullable=False)
    qr_hash = Column(String(200), nullable=False)
    verified_at = Column(DateTime, default=datetime.utcnow)

    order = relationship("TableOrder", back_populates="verifications")


class MobileVerifyToken(Base):
    """태블릿 → 고객 폰 QR 인증 토큰 (1회용, 10분 유효)"""
    __tablename__ = "mobile_verify_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    order_id = Column(UUID(as_uuid=True), ForeignKey("table_orders.id"), nullable=False)
    token = Column(String(100), unique=True, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)

    order = relationship("TableOrder", back_populates="mobile_tokens")
