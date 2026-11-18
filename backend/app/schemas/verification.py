from pydantic import BaseModel
from uuid import UUID
from datetime import datetime
from ..models.verification import VerificationStatus


class VerificationSessionCreate(BaseModel):
    merchant_id: UUID | None = None


class VerificationSessionResponse(BaseModel):
    id: UUID
    status: VerificationStatus
    id_check_result: bool | None
    phone_check_result: bool | None
    biometric_check_result: bool | None
    created_at: datetime

    model_config = {"from_attributes": True}


class IDCheckResponse(BaseModel):
    session_id: UUID
    is_genuine: bool
    confidence: float
    id_type: str
    detail: dict


class BiometricRegisterResponse(BaseModel):
    success: bool
    face_registered: bool
    fingerprint_registered: bool
    message: str


class BiometricVerifyResponse(BaseModel):
    session_id: UUID
    matched: bool
    method: str   # "face" | "fingerprint"
    score: float
