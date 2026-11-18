import uuid
from sqlalchemy import Column, String, Boolean, Integer, ForeignKey, Text, Float
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from ..core.database import Base


class MenuCategory(Base):
    __tablename__ = "menu_categories"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    merchant_id = Column(UUID(as_uuid=True), ForeignKey("merchants.id"), nullable=False)
    name = Column(String(50), nullable=False)
    sort_order = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)

    merchant = relationship("Merchant", back_populates="menu_categories")
    items = relationship("MenuItem", back_populates="category", cascade="all, delete-orphan")


class MenuItem(Base):
    __tablename__ = "menu_items"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    merchant_id = Column(UUID(as_uuid=True), ForeignKey("merchants.id"), nullable=False)
    category_id = Column(UUID(as_uuid=True), ForeignKey("menu_categories.id"), nullable=True)
    name = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)
    price = Column(Integer, nullable=False)           # 원 단위
    image_url = Column(String(500), nullable=True)
    is_adult_only = Column(Boolean, default=False)    # 성인 전용 (주류 등)
    is_available = Column(Boolean, default=True)
    sort_order = Column(Integer, default=0)

    merchant = relationship("Merchant", back_populates="menu_items")
    category = relationship("MenuCategory", back_populates="items")
