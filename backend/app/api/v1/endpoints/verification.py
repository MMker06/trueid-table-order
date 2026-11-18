from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy.orm import Session

from ....core.database import get_db
from ....models.merchant import Merchant
from ....models.verification import VerificationSession, VerificationStatus
from ....models.id_check import IDCheckLog
from ....models.user import User
from ....schemas.verification import (
    VerificationSessionCreate, VerificationSessionResponse, IDCheckResponse,
)
from ....services.id_verification.preprocessor import load_image, normalize, detect_and_crop_id
from ....services.id_verification.ai_analyzer import get_analyzer
from ..endpoints.auth import get_current_user

router = APIRouter(prefix="/verification", tags=["신분증 인증"])

MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB


@router.post("/session", response_model=VerificationSessionResponse, status_code=201)
def create_session(
    req: VerificationSessionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if req.merchant_id:
        merchant = db.query(Merchant).filter(
            Merchant.id == req.merchant_id, Merchant.is_trueid_active == True
        ).first()
        if not merchant:
            raise HTTPException(status_code=404, detail="유효하지 않은 매장입니다.")

    session = VerificationSession(
        user_id=current_user.id,
        merchant_id=req.merchant_id,
        status=VerificationStatus.PENDING,
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return session


@router.post("/id-check/{session_id}", response_model=IDCheckResponse)
async def check_id_card(
    session_id: UUID,
    image: UploadFile = File(..., description="신분증 이미지 (JPEG/PNG)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = db.query(VerificationSession).filter(
        VerificationSession.id == session_id,
        VerificationSession.user_id == current_user.id,
    ).first()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    if session.status not in (VerificationStatus.PENDING,):
        raise HTTPException(status_code=400, detail="이미 처리된 세션입니다.")

    allowed = {"image/jpeg", "image/png", "image/webp", "application/octet-stream", "image/jpg"}
    if image.content_type and image.content_type not in allowed:
        raise HTTPException(status_code=422, detail="JPEG, PNG, WEBP 이미지만 허용됩니다.")

    raw = await image.read()
    if len(raw) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=413, detail="이미지 크기가 10MB를 초과합니다.")

    # 전처리
    try:
        img = load_image(raw)
    except (ValueError, Exception) as e:
        raise HTTPException(status_code=422, detail=f"이미지를 읽을 수 없습니다: {e}")

    try:
        img = normalize(img)
        cropped, found = detect_and_crop_id(img)
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"이미지 전처리 오류: {e}")

    # AI 분석
    try:
        result = get_analyzer().analyze(cropped)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"AI 분석 오류: {e}")

    # 결과 저장
    log = IDCheckLog(
        user_id=current_user.id,
        merchant_id=session.merchant_id,
        is_genuine=result.is_genuine,
        confidence_score=result.confidence,
        id_type=result.id_type,
        analysis_detail=result.detail,
    )
    db.add(log)

    session.id_check_result = result.is_genuine
    if result.is_genuine:
        session.status = VerificationStatus.ID_VERIFIED
    else:
        session.status = VerificationStatus.FAILED
        session.completed_at = datetime.utcnow()
    db.commit()

    return IDCheckResponse(
        session_id=session_id,
        is_genuine=result.is_genuine,
        confidence=result.confidence,
        id_type=result.id_type,
        detail=result.detail,
    )


@router.get("/session/{session_id}", response_model=VerificationSessionResponse)
def get_session(
    session_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = db.query(VerificationSession).filter(
        VerificationSession.id == session_id,
        VerificationSession.user_id == current_user.id,
    ).first()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    return session
