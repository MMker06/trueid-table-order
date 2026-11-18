import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from ..core.database import Base
import enum


class UserRole(str, enum.Enum):
    CUSTOMER = "customer"
    MERCHANT = "merchant"
    ADMIN = "admin"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    phone = Column(String(20), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=True)
    hashed_password = Column(String(255), nullable=False)
    name = Column(String(100), nullable=False)
    role = Column(SAEnum(UserRole), default=UserRole.MERCHANT, nullable=False)
    is_active = Column(Boolean, default=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
