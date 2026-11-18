from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from ....core.database import get_db
from ....models.menu import MenuCategory, MenuItem
from ....models.merchant import Merchant
from ..endpoints.auth import get_current_user
from ....models.user import User

router = APIRouter(prefix="/menu", tags=["메뉴"])


class CategoryCreate(BaseModel):
    name: str
    sort_order: int = 0

class MenuItemCreate(BaseModel):
    category_id: Optional[UUID] = None
    name: str
    description: Optional[str] = None
    price: int
    is_adult_only: bool = False
    is_available: bool = True
    sort_order: int = 0

class MenuItemUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    price: Optional[int] = None
    is_adult_only: Optional[bool] = None
    is_available: Optional[bool] = None
    category_id: Optional[UUID] = None


def _get_merchant(user: User, db: Session) -> Merchant:
    m = db.query(Merchant).filter(Merchant.user_id == user.id).first()
    if not m:
        raise HTTPException(404, "매장 정보가 없습니다.")
    return m


@router.get("/public/{merchant_id}")
def get_public_menu(merchant_id: UUID, db: Session = Depends(get_db)):
    """고객용 메뉴판 — 인증 불필요"""
    categories = db.query(MenuCategory).filter(
        MenuCategory.merchant_id == merchant_id,
        MenuCategory.is_active == True,
    ).order_by(MenuCategory.sort_order).all()

    result = []
    for cat in categories:
        items = db.query(MenuItem).filter(
            MenuItem.category_id == cat.id,
            MenuItem.is_available == True,
        ).order_by(MenuItem.sort_order).all()
        result.append({
            "id": str(cat.id),
            "name": cat.name,
            "items": [_item_dict(i) for i in items],
        })

    # 카테고리 없는 메뉴
    uncategorized = db.query(MenuItem).filter(
        MenuItem.merchant_id == merchant_id,
        MenuItem.category_id == None,
        MenuItem.is_available == True,
    ).all()
    if uncategorized:
        result.insert(0, {
            "id": None,
            "name": "전체",
            "items": [_item_dict(i) for i in uncategorized],
        })
    return result


@router.get("/categories")
def list_categories(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    m = _get_merchant(user, db)
    cats = db.query(MenuCategory).filter(MenuCategory.merchant_id == m.id).order_by(MenuCategory.sort_order).all()
    return [{"id": str(c.id), "name": c.name, "sort_order": c.sort_order, "is_active": c.is_active} for c in cats]


@router.post("/categories", status_code=201)
def create_category(body: CategoryCreate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    m = _get_merchant(user, db)
    cat = MenuCategory(merchant_id=m.id, name=body.name, sort_order=body.sort_order)
    db.add(cat); db.commit(); db.refresh(cat)
    return {"id": str(cat.id), "name": cat.name}


@router.get("/items")
def list_items(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    m = _get_merchant(user, db)
    items = db.query(MenuItem).filter(MenuItem.merchant_id == m.id).order_by(MenuItem.sort_order).all()
    return [_item_dict(i) for i in items]


@router.post("/items", status_code=201)
def create_item(body: MenuItemCreate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    m = _get_merchant(user, db)
    item = MenuItem(merchant_id=m.id, **body.model_dump())
    db.add(item); db.commit(); db.refresh(item)
    return _item_dict(item)


@router.patch("/items/{item_id}")
def update_item(item_id: UUID, body: MenuItemUpdate, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    m = _get_merchant(user, db)
    item = db.query(MenuItem).filter(MenuItem.id == item_id, MenuItem.merchant_id == m.id).first()
    if not item:
        raise HTTPException(404, "메뉴를 찾을 수 없습니다.")
    for k, v in body.model_dump(exclude_none=True).items():
        setattr(item, k, v)
    db.commit(); db.refresh(item)
    return _item_dict(item)


@router.delete("/items/{item_id}", status_code=204)
def delete_item(item_id: UUID, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    m = _get_merchant(user, db)
    item = db.query(MenuItem).filter(MenuItem.id == item_id, MenuItem.merchant_id == m.id).first()
    if not item:
        raise HTTPException(404, "메뉴를 찾을 수 없습니다.")
    db.delete(item); db.commit()


def _item_dict(i: MenuItem) -> dict:
    return {
        "id": str(i.id),
        "name": i.name,
        "description": i.description,
        "price": i.price,
        "is_adult_only": i.is_adult_only,
        "is_available": i.is_available,
        "category_id": str(i.category_id) if i.category_id else None,
        "image_url": i.image_url,
        "sort_order": i.sort_order,
    }
