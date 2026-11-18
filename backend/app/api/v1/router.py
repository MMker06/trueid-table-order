from fastapi import APIRouter
from .endpoints import auth, merchant, menu, orders, ai_detect

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(merchant.router)
api_router.include_router(menu.router)
api_router.include_router(orders.router)
api_router.include_router(ai_detect.router)
