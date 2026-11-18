from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional

from ....core.database import get_db
from ....models.merchant import Merchant
from ....models.user import User
from ..endpoints.auth import get_current_user

router = APIRouter(prefix="/merchant", tags=["매장 관리"])


class MerchantCreate(BaseModel):
    business_name: str
    business_number: str
    address: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    category: Optional[str] = None


@router.post("/register", status_code=201)
def register_merchant(body: MerchantCreate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    existing = db.query(Merchant).filter(Merchant.user_id == user.id).first()
    if existing:
        raise HTTPException(400, "이미 등록된 매장이 있습니다.")
    m = Merchant(user_id=user.id, **body.model_dump())
    db.add(m); db.commit(); db.refresh(m)
    return _merchant_dict(m)


@router.get("/me")
def get_my_merchant(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    m = db.query(Merchant).filter(Merchant.user_id == user.id).first()
    if not m:
        raise HTTPException(404, "매장 정보가 없습니다.")
    return _merchant_dict(m)


@router.get("/{merchant_id}/public")
def get_merchant_public(merchant_id: UUID, db: Session = Depends(get_db)):
    m = db.query(Merchant).filter(Merchant.id == merchant_id).first()
    if not m:
        raise HTTPException(404, "매장을 찾을 수 없습니다.")
    return {"id": str(m.id), "business_name": m.business_name, "category": m.category}


def _merchant_dict(m: Merchant) -> dict:
    return {
        "id": str(m.id),
        "business_name": m.business_name,
        "business_number": m.business_number,
        "address": m.address,
        "category": m.category,
        "is_active": m.is_active,
    }
