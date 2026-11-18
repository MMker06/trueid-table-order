from fastapi import APIRouter, File, UploadFile, HTTPException
import cv2
import numpy as np
from pathlib import Path

router = APIRouter(prefix="/ai", tags=["AI 감지"])

_FREE_PASS_AGE = 50   # 이 나이 이상이면 신분증 인증 면제

# ── InsightFace 앱 (지연 로딩) ──────────────────────────────────
_face_app = None


def _get_face_app():
    global _face_app
    if _face_app is None:
        import insightface
        _face_app = insightface.app.FaceAnalysis(
            name="buffalo_s",
            providers=["CPUExecutionProvider"],
            root="/root/.insightface",
        )
        _face_app.prepare(ctx_id=0, det_size=(320, 320))
        print("[InsightFace] 모델 로드 완료")
    return _face_app


def _load_image(data: bytes) -> np.ndarray:
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(422, "이미지를 읽을 수 없습니다.")
    return img


@router.post("/estimate-age")
async def estimate_age(image: UploadFile = File(...)):
    raw = await image.read()
    img = _load_image(raw)

    app = _get_face_app()
    faces = app.get(img)

    if not faces:
        return {
            "detected": False,
            "free_pass": False,
            "reason": "얼굴이 감지되지 않았습니다. 카메라를 얼굴 정면에 맞춰주세요.",
        }

    # 가장 큰 얼굴 선택
    face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
    age = int(round(float(face.age)))
    free_pass = age >= _FREE_PASS_AGE

    label = f"{age}세"
    reason = (
        "AI 분석 완료 — 인증 면제"
        if free_pass
        else "AI 분석 완료 — 신분증 확인 필요"
    )

    return {
        "detected":   True,
        "class":      f"{_FREE_PASS_AGE}이상" if free_pass else f"{_FREE_PASS_AGE}미만",
        "age":        age,
        "free_pass":  free_pass,
        "reason":     reason,
    }


@router.get("/model-status")
def model_status_endpoint():
    loaded = _face_app is not None
    return {
        "insightface": {
            "loaded": loaded,
            "model": "buffalo_s",
            "free_pass_age": _FREE_PASS_AGE,
        }
    }


@router.post("/verify-id")
async def verify_id(image: UploadFile = File(...)):
    raw = await image.read()
    arr = np.frombuffer(raw, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(422, "이미지를 읽을 수 없습니다.")
    from .ocr_id import extract_age_from_id
    result = extract_age_from_id(img)
    if not result["found"]:
        return {"verified": False, "reason": "신분증에서 생년월일을 읽지 못했습니다.", "raw": result.get("raw", "")}
    age = result["age"]
    is_adult = result["is_adult"]
    return {
        "verified": True,
        "age": age,
        "is_adult": is_adult,
        "method": result.get("method"),
        "reason": f"만 {age}세 — {'성인 인증 완료' if is_adult else '미성년자'}",
    }


@router.get("/cert-qr/generate")
def cert_qr_generate(birth_date: str):
    from .cert_qr import generate as _gen
    try:
        qr_data = _gen(birth_date)
        return {"qr_data": qr_data, "birth_date": birth_date}
    except Exception as e:
        raise HTTPException(400, f"QR 생성 실패: {e}")


@router.post("/detect-people")
async def detect_people(image: UploadFile = File(...)):
    raw = await image.read()
    img = _load_image(raw)
    try:
        from ultralytics import YOLO
        _people_model = YOLO("yolov8n.pt")
        results = _people_model(img, classes=[0], conf=0.4, verbose=False)
        count = len(results[0].boxes) if results[0].boxes else 0
    except Exception:
        count = 0
    return {"people_count": count, "detected": count > 0}


def warmup():
    try:
        _get_face_app()
    except Exception as e:
        print(f"[InsightFace] 워밍업 실패: {e}")
