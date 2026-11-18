from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from jose import JWTError

from ....core.database import get_db
from ....core.security import hash_password, verify_password, create_access_token, create_refresh_token, decode_token
from ....models.user import User, UserRole

router = APIRouter(prefix="/auth", tags=["인증"])
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            raise HTTPException(401, "유효하지 않은 토큰 타입")
        user_id = payload.get("sub")
    except JWTError:
        raise HTTPException(401, "토큰 검증 실패")
    user = db.query(User).filter(User.id == user_id, User.is_active == True).first()
    if not user:
        raise HTTPException(401, "사용자를 찾을 수 없습니다.")
    return user


class SignupRequest(BaseModel):
    phone: str
    name: str
    password: str

class LoginRequest(BaseModel):
    phone: str
    password: str

class RefreshRequest(BaseModel):
    refresh_token: str

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


@router.post("/signup", response_model=TokenResponse, status_code=201)
def signup(req: SignupRequest, db: Session = Depends(get_db)):
    if db.query(User).filter(User.phone == req.phone).first():
        raise HTTPException(409, "이미 가입된 전화번호입니다.")
    user = User(phone=req.phone, name=req.name, hashed_password=hash_password(req.password), role=UserRole.MERCHANT)
    db.add(user); db.commit(); db.refresh(user)
    return TokenResponse(
        access_token=create_access_token({"sub": str(user.id)}),
        refresh_token=create_refresh_token({"sub": str(user.id)}),
    )


@router.post("/login", response_model=TokenResponse)
def login(req: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.phone == req.phone).first()
    if not user or not verify_password(req.password, user.hashed_password):
        raise HTTPException(401, "전화번호 또는 비밀번호가 올바르지 않습니다.")
    return TokenResponse(
        access_token=create_access_token({"sub": str(user.id)}),
        refresh_token=create_refresh_token({"sub": str(user.id)}),
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(req: RefreshRequest, db: Session = Depends(get_db)):
    try:
        payload = decode_token(req.refresh_token)
        if payload.get("type") != "refresh":
            raise HTTPException(401, "유효하지 않은 리프레시 토큰")
        user_id = payload.get("sub")
    except JWTError:
        raise HTTPException(401, "토큰 검증 실패")
    user = db.query(User).filter(User.id == user_id, User.is_active == True).first()
    if not user:
        raise HTTPException(401, "사용자를 찾을 수 없습니다.")
    return TokenResponse(
        access_token=create_access_token({"sub": str(user.id)}),
        refresh_token=create_refresh_token({"sub": str(user.id)}),
    )


@router.get("/me")
def get_me(user: User = Depends(get_current_user)):
    return {"id": str(user.id), "phone": user.phone, "name": user.name, "role": user.role.value}
