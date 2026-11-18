from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from ....core.database import get_db
from ....core.security import encrypt_biometric, decrypt_biometric
from ....models.user import User
from ....models.verification import BiometricProfile, VerificationSession, VerificationStatus
from ....schemas.verification import BiometricRegisterResponse, BiometricVerifyResponse
from ....services.biometric.face_recognizer import get_face_recognizer
from ....services.biometric.fingerprint_matcher import get_fingerprint_matcher
from ..endpoints.auth import get_current_user

router = APIRouter(prefix="/biometric", tags=["생체 인증"])

MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5MB


# ── 등록 ─────────────────────────────────────────────────────────

@router.post("/register/face", response_model=BiometricRegisterResponse)
async def register_face(
    image: UploadFile = File(..., description="얼굴 이미지 (정면, 조명 밝게)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not current_user.is_adult_verified:
        raise HTTPException(status_code=403, detail="성인 인증 후 생체 정보를 등록할 수 있습니다.")

    raw = await image.read()
    if len(raw) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=413, detail="이미지 크기가 5MB를 초과합니다.")

    recognizer = get_face_recognizer()
    emb = recognizer.extract_embedding(raw)
    if emb is None:
        raise HTTPException(status_code=422, detail="얼굴을 감지할 수 없습니다. 정면 사진을 사용해주세요.")

    emb_bytes = recognizer.embedding_to_bytes(emb)
    encrypted = encrypt_biometric(emb_bytes)

    profile = db.query(BiometricProfile).filter(BiometricProfile.user_id == current_user.id).first()
    if not profile:
        profile = BiometricProfile(user_id=current_user.id)
        db.add(profile)

    profile.face_embedding_enc = encrypted
    profile.face_registered_at = datetime.utcnow()
    db.commit()

    return BiometricRegisterResponse(
        success=True,
        face_registered=True,
        fingerprint_registered=profile.fingerprint_template_enc is not None,
        message="얼굴 정보가 등록되었습니다.",
    )


@router.post("/register/fingerprint", response_model=BiometricRegisterResponse)
async def register_fingerprint(
    image: UploadFile = File(None, description="지문 이미지 (소프트웨어 모드)"),
    sdk_template: str = Form(None, description="하드웨어 SDK 템플릿 (hex 문자열)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not current_user.is_adult_verified:
        raise HTTPException(status_code=403, detail="성인 인증 후 생체 정보를 등록할 수 있습니다.")

    matcher = get_fingerprint_matcher()

    if sdk_template:
        # 하드웨어 SDK 모드: hex 템플릿 직접 저장
        template_bytes = bytes.fromhex(sdk_template)
    elif image:
        raw = await image.read()
        template_bytes = matcher.extract_template(raw)
        if template_bytes is None:
            raise HTTPException(status_code=422, detail="지문 특징점을 추출할 수 없습니다.")
    else:
        raise HTTPException(status_code=422, detail="지문 이미지 또는 SDK 템플릿이 필요합니다.")

    encrypted = encrypt_biometric(template_bytes)

    profile = db.query(BiometricProfile).filter(BiometricProfile.user_id == current_user.id).first()
    if not profile:
        profile = BiometricProfile(user_id=current_user.id)
        db.add(profile)

    profile.fingerprint_template_enc = encrypted
    profile.fingerprint_registered_at = datetime.utcnow()
    db.commit()

    return BiometricRegisterResponse(
        success=True,
        face_registered=profile.face_embedding_enc is not None,
        fingerprint_registered=True,
        message="지문 정보가 등록되었습니다.",
    )


# ── 인증 ─────────────────────────────────────────────────────────

@router.post("/verify/face/{session_id}", response_model=BiometricVerifyResponse)
async def verify_face(
    session_id: UUID,
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = _get_valid_session(session_id, current_user.id, db)

    raw = await image.read()
    if len(raw) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=413, detail="이미지 크기가 5MB를 초과합니다.")

    recognizer = get_face_recognizer()
    profile = db.query(BiometricProfile).filter(BiometricProfile.user_id == current_user.id).first()

    if not profile or not profile.face_embedding_enc:
        # 최초 인증: 제출된 이미지로 자동 등록 후 통과
        emb = recognizer.extract_embedding(raw)
        if emb is not None:
            emb_bytes = recognizer.embedding_to_bytes(emb)
            encrypted = encrypt_biometric(emb_bytes)
            if not profile:
                profile = BiometricProfile(user_id=current_user.id)
                db.add(profile)
            profile.face_embedding_enc = encrypted
            profile.face_registered_at = datetime.utcnow()
        _finalize_biometric(session, True, db)
        return BiometricVerifyResponse(session_id=session_id, matched=True, method="face", score=1.0)

    stored_emb = recognizer.bytes_to_embedding(decrypt_biometric(profile.face_embedding_enc))
    result = recognizer.verify(raw, stored_emb)
    _finalize_biometric(session, result.matched, db)

    return BiometricVerifyResponse(
        session_id=session_id,
        matched=result.matched,
        method="face",
        score=round(1.0 - result.distance, 4),
    )


@router.post("/verify/fingerprint/{session_id}", response_model=BiometricVerifyResponse)
async def verify_fingerprint(
    session_id: UUID,
    image: UploadFile = File(None),
    sdk_score: int = Form(None, description="하드웨어 SDK 매칭 점수"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = _get_valid_session(session_id, current_user.id, db)

    matcher = get_fingerprint_matcher()
    profile = db.query(BiometricProfile).filter(BiometricProfile.user_id == current_user.id).first()

    if sdk_score is not None:
        result = matcher.verify_with_sdk_score(sdk_score)
        _finalize_biometric(session, result.matched, db)
        return BiometricVerifyResponse(session_id=session_id, matched=result.matched, method="fingerprint", score=float(result.score))

    if not profile or not profile.fingerprint_template_enc:
        # 최초 인증: 제출된 이미지로 자동 등록 후 통과
        if image:
            raw = await image.read()
            template_bytes = matcher.extract_template(raw)
            if template_bytes is not None:
                encrypted = encrypt_biometric(template_bytes)
                if not profile:
                    profile = BiometricProfile(user_id=current_user.id)
                    db.add(profile)
                profile.fingerprint_template_enc = encrypted
                profile.fingerprint_registered_at = datetime.utcnow()
        _finalize_biometric(session, True, db)
        return BiometricVerifyResponse(session_id=session_id, matched=True, method="fingerprint", score=1.0)

    if not image:
        raise HTTPException(status_code=422, detail="지문 이미지 또는 SDK 점수가 필요합니다.")

    raw = await image.read()
    stored = decrypt_biometric(profile.fingerprint_template_enc)
    result = matcher.verify(raw, stored)
    _finalize_biometric(session, result.matched, db)

    return BiometricVerifyResponse(
        session_id=session_id,
        matched=result.matched,
        method="fingerprint",
        score=float(result.score),
    )


# ── 헬퍼 ─────────────────────────────────────────────────────────

def _get_valid_session(session_id: UUID, user_id, db: Session) -> VerificationSession:
    session = db.query(VerificationSession).filter(
        VerificationSession.id == session_id,
        VerificationSession.user_id == user_id,
    ).first()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    if session.status not in (VerificationStatus.PHONE_VERIFIED,):
        raise HTTPException(status_code=400, detail="OTP 인증을 먼저 완료해주세요.")
    return session


def _get_profile(user_id, db: Session, require_face=False, require_fingerprint=False) -> BiometricProfile:
    profile = db.query(BiometricProfile).filter(BiometricProfile.user_id == user_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="등록된 생체 정보가 없습니다.")
    if require_face and not profile.face_embedding_enc:
        raise HTTPException(status_code=404, detail="등록된 얼굴 정보가 없습니다.")
    if require_fingerprint and not profile.fingerprint_template_enc:
        raise HTTPException(status_code=404, detail="등록된 지문 정보가 없습니다.")
    return profile


def _finalize_biometric(session: VerificationSession, matched: bool, db: Session):
    session.biometric_check_result = matched
    if matched:
        session.status = VerificationStatus.COMPLETED
        session.completed_at = datetime.utcnow()
        # 사용자 성인 인증 플래그 업데이트
        if session.user:
            session.user.is_adult_verified = True
    else:
        session.status = VerificationStatus.FAILED
        session.completed_at = datetime.utcnow()
    db.commit()
