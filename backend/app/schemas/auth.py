from pydantic import BaseModel, field_validator
import re


class SignupRequest(BaseModel):
    phone: str
    password: str
    name: str
    email: str | None = None

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        cleaned = re.sub(r"[^0-9]", "", v)
        if not re.match(r"^01[0-9]{8,9}$", cleaned):
            raise ValueError("유효하지 않은 휴대폰 번호입니다.")
        return cleaned

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("비밀번호는 8자 이상이어야 합니다.")
        return v


class LoginRequest(BaseModel):
    phone: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


class OTPSendRequest(BaseModel):
    phone: str
    session_id: str


class OTPVerifyRequest(BaseModel):
    session_id: str
    otp_code: str
