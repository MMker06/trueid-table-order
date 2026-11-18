import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Float, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from ..core.database import Base


class Merchant(Base):
    __tablename__ = "merchants"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    business_name = Column(String(200), nullable=False)
    business_number = Column(String(20), unique=True, nullable=False)
    address = Column(String(500), nullable=False)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    category = Column(String(100), nullable=True)
    is_active = Column(Boolean, default=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", foreign_keys=[user_id])
    menu_categories = relationship("MenuCategory", back_populates="merchant", cascade="all, delete-orphan")
    menu_items = relationship("MenuItem", back_populates="merchant", cascade="all, delete-orphan")
    orders = relationship("TableOrder", back_populates="merchant", cascade="all, delete-orphan")
