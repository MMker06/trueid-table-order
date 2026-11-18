"""
커스텀 AI 모델 로더
===================
사용 방법:
  /home/ubuntu/trueid/backend/models/ 디렉터리에 .pt 파일을 복사하면 자동 로드됩니다.

  face_age.pt   — 얼굴 나이 예측 모델
  id_verify.pt  — 신분증 위조 판별 + 성인 인증 모델

─────────────────────────────────────────────────
■ face_age.pt 입출력 규격
  입력: torch.Tensor  shape [1, 3, 224, 224]
        dtype float32, RGB, 값 범위 0.0~1.0
        (ImageNet 정규화 적용: mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225])

  출력 (아래 중 하나 — 자동 판별):
    A. Tensor [1]      → 나이 실수값 (예: 35.7)
    B. Tensor [1, 1]   → 나이 실수값
    C. Tensor [1, N]   → N개 나이 클래스의 로짓/확률 (0세~N-1세 가중평균)

─────────────────────────────────────────────────
■ id_verify.pt 입출력 규격
  입력: torch.Tensor  shape [1, 3, 224, 224]
        dtype float32, RGB, 값 범위 0.0~1.0
        (ImageNet 정규화 적용)

  출력 (아래 중 하나 — 자동 판별):
    A. Tensor [1, 2]   → [fake_logit, real_logit]  (softmax → real_prob)
    B. Tensor [1]      → sigmoid → real_prob
    C. tuple/list      → (fake_prob, real_prob) 또는 (real_prob, adult_prob)
    D. dict            → {'is_real': float, 'is_adult': float, 'confidence': float}

─────────────────────────────────────────────────
■ 모델 파일 경로
  /home/ubuntu/trueid/backend/models/face_age.pt
  /home/ubuntu/trueid/backend/models/id_verify.pt
"""

from __future__ import annotations
import os
import logging
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
import torch

logger = logging.getLogger(__name__)

MODEL_DIR = Path(__file__).resolve().parents[4] / "models"

# 허용 확장자 (.pt / .pth 모두 지원)
_EXTS = [".pt", ".pth"]

# ImageNet 정규화 상수 (커스텀 모델이 자체 mean/std 없을 때 폴백)
_MEAN = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
_STD  = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)


def _load_custom_class():
    """
    models/model_class.py 에서 MODEL_CLASS 를 동적 임포트.
    파일이 없거나 MODEL_CLASS=None 이면 None 반환.
    """
    class_file = MODEL_DIR / "model_class.py"
    if not class_file.exists():
        return None
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("model_class", class_file)
        mod  = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        cls = getattr(mod, "MODEL_CLASS", None)
        if cls is None:
            # MODEL_CLASS 미할당 → 파일 내 nn.Module 서브클래스 자동 탐색
            import inspect, torch.nn as nn
            candidates = [v for _, v in inspect.getmembers(mod, inspect.isclass)
                          if issubclass(v, nn.Module) and v is not nn.Module]
            cls = candidates[0] if candidates else None
        if cls is not None:
            logger.info(f"[CustomClass] {cls.__name__} 로드 완료")
        return cls
    except Exception as e:
        logger.error(f"[CustomClass] model_class.py 로드 실패: {e}")
        return None


def _load_custom_model(path: Path):
    """
    models/model_class.py 의 클래스로 best.pt / *.pt 를 로드.
    체크포인트에 mean/std 있으면 그것도 같이 반환.
    """
    cls = _load_custom_class()
    if cls is None:
        return None
    try:
        ckpt = torch.load(str(path), map_location="cpu", weights_only=False)
        sd   = ckpt.get("state_dict") or ckpt.get("model_state_dict")
        if sd is None:
            return None
        model = cls()
        model.load_state_dict(sd)
        model.eval()
        mean = ckpt.get("mean")
        std  = ckpt.get("std")
        classes = ckpt.get("classes", ["30이하", "40이상"])
        logger.info(f"[CustomModel] {cls.__name__} 로드 완료 | "
                    f"accuracy={ckpt.get('test_accuracy', '?')} | classes={classes}")
        return ("custom_class", model, classes, mean, std)
    except Exception as e:
        logger.error(f"[CustomModel] 로드 실패: {e}")
        return None


# ── 공통 유틸 ─────────────────────────────────────────────────

def _find_model_file(stem: str) -> Optional[Path]:
    """stem 이름으로 .pt / .pth 파일을 찾아 반환"""
    for ext in _EXTS:
        p = MODEL_DIR / f"{stem}{ext}"
        if p.exists():
            return p
    return None


def _restore_from_state_dict(state_dict, num_classes: int) -> Optional[torch.nn.Module]:
    """
    state_dict 키 패턴으로 아키텍처를 추론해 모델 복원.
    지원: EfficientNet-B0/B1, MobileNetV2, MobileNetV3-Large, ResNet18/50
    """
    keys = list(state_dict.keys())
    try:
        from torchvision import models

        # EfficientNet-B0: features.0.0.weight [32,3,3,3] + features.8 존재
        if "features.0.0.weight" in keys and any("features.8" in k for k in keys):
            w0 = state_dict["features.0.0.weight"]
            model = models.efficientnet_b0(weights=None) if w0.shape[0] == 32 \
                    else models.efficientnet_b1(weights=None)
            model.classifier[1] = torch.nn.Linear(1280, num_classes)
            model.load_state_dict(state_dict)
            model.eval()
            return model

        # MobileNetV2: features.X.conv.0.0.weight 패턴
        if any("conv.0.0.weight" in k for k in keys):
            model = models.mobilenet_v2(weights=None)
            model.classifier[1] = torch.nn.Linear(1280, num_classes)
            model.load_state_dict(state_dict)
            model.eval()
            return model

        # MobileNetV3-Large: block.X.0.weight + classifier.3.weight
        if any("block.0.0.weight" in k for k in keys) and "classifier.3.weight" in keys:
            model = models.mobilenet_v3_large(weights=None)
            model.classifier[3] = torch.nn.Linear(1280, num_classes)
            model.load_state_dict(state_dict)
            model.eval()
            return model

        # ResNet: layer1.0.conv1.weight
        if "layer1.0.conv1.weight" in keys:
            model = (models.resnet50 if "layer4.2.conv1.weight" in keys
                     else models.resnet18)(weights=None)
            model.fc = torch.nn.Linear(model.fc.in_features, num_classes)
            model.load_state_dict(state_dict)
            model.eval()
            return model

    except Exception as e:
        logger.error(f"[복원] {e}")
    return None


def _load_pt(path: Path) -> Optional[tuple]:
    """
    로드 순서:
      1) TorchScript (torch.jit.load)
      2) nn.Module (torch.load)
      3) dict{'model_state_dict','classes'} → 아키텍처 자동 복원
      4) YOLO (ultralytics)
    """
    if not path.exists():
        return None

    # 1) TorchScript
    try:
        m = torch.jit.load(str(path), map_location="cpu")
        m.eval()
        logger.info(f"[모델] TorchScript 로드: {path.name}")
        return ("torchscript", m, [])
    except Exception:
        pass

    # 2 & 3) torch.load
    try:
        obj = torch.load(str(path), map_location="cpu", weights_only=False)

        if isinstance(obj, torch.nn.Module):
            obj.eval()
            logger.info(f"[모델] nn.Module 로드: {path.name}")
            return ("module", obj, [])

        if isinstance(obj, dict) and "model_state_dict" in obj:
            classes = obj.get("classes", [])
            model = _restore_from_state_dict(obj["model_state_dict"], len(classes))
            if model is not None:
                logger.info(f"[모델] state_dict 복원: {path.name} | 클래스={classes}")
                return ("module", model, classes)
            logger.warning(f"[모델] state_dict 복원 실패: {path.name}")
            return None

        logger.warning(f"[모델] 알 수 없는 형식: {type(obj).__name__} — {path.name}")
        return None

    except Exception as e:
        logger.warning(f"[모델] torch.load 실패: {path.name} — {e}")

    # 4) YOLO
    try:
        from ultralytics import YOLO
        m = YOLO(str(path))
        logger.info(f"[모델] YOLO 로드: {path.name}")
        return ("yolo", m, [])
    except Exception as e:
        logger.warning(f"[모델] YOLO 로드 실패: {path.name} — {e}")

    return None


def _preprocess(img_bgr: np.ndarray, size: int = 224) -> torch.Tensor:
    """BGR numpy → ImageNet 정규화된 RGB tensor [1,3,H,W]"""
    img = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    img = cv2.resize(img, (size, size), interpolation=cv2.INTER_LINEAR)
    t = torch.from_numpy(img).float().div(255.0)   # [H,W,3] 0~1
    t = t.permute(2, 0, 1).unsqueeze(0)            # [1,3,H,W]
    t = (t - _MEAN) / _STD                         # ImageNet 정규화
    return t


# ── 얼굴 나이 예측 ─────────────────────────────────────────────

_face_age_cache: Optional[tuple] = None

def get_face_age_model():
    global _face_age_cache
    if _face_age_cache is None:
        # 1순위: best.pt + model_class.py 조합
        best = MODEL_DIR / "best.pt"
        if best.exists():
            _face_age_cache = _load_custom_model(best)

        # 2순위: face_age.pt / face_age.pth (EfficientNet 자동복원)
        if _face_age_cache is None:
            p = _find_model_file("face_age")
            if p:
                _face_age_cache = _load_pt(p)

        if _face_age_cache is None:
            logger.info("[FaceAge] 로드된 모델 없음")
    return _face_age_cache


def predict_age(img_bgr: np.ndarray,
                face_bbox: Optional[tuple] = None) -> dict:
    """
    얼굴 이미지에서 나이 예측

    Parameters
    ----------
    img_bgr   : BGR numpy 이미지 (전체 프레임 또는 이미 크롭된 얼굴)
    face_bbox : (x1, y1, x2, y2) InsightFace 얼굴 박스 — 있으면 크롭 후 예측

    Returns
    -------
    {
      'age'       : float | None,
      'free_pass' : bool,          # 40세 이상이면 True
      'is_adult'  : bool | None,   # 19세 이상이면 True
      'model'     : 'custom' | 'none',
    }
    """
    model_tuple = get_face_age_model()
    if model_tuple is None:
        return {"age": None, "free_pass": False, "is_adult": None, "model": "none"}

    kind    = model_tuple[0]
    model   = model_tuple[1]
    classes = model_tuple[2]

    # 얼굴 크롭
    if face_bbox is not None:
        x1, y1, x2, y2 = [int(v) for v in face_bbox]
        pad = 20
        h, w = img_bgr.shape[:2]
        crop = img_bgr[max(0, y1 - pad):min(h, y2 + pad),
                       max(0, x1 - pad):min(w, x2 + pad)]
        if crop.size == 0:
            crop = img_bgr
    else:
        crop = img_bgr

    try:
        if kind == "yolo":
            results = model(crop, verbose=False)
            probs = results[0].probs
            if probs is None:
                return {"age": None, "free_pass": False, "is_adult": None, "model": "custom"}
            age = float(probs.top1)
            return {
                "age": None, "free_pass": age >= 40,
                "is_adult": True, "model": "custom",
                "class": classes[int(age)] if classes else str(int(age)),
                "confidence": round(float(probs.top1conf.item()), 3),
            }

        # custom_class 또는 module — 전처리 mean/std 결정
        if kind == "custom_class" and len(model_tuple) >= 5:
            raw_mean, raw_std = model_tuple[3], model_tuple[4]
            if raw_mean is not None and raw_std is not None:
                mean = torch.tensor([raw_mean]).view(1, 1, 1, 1)
                std  = torch.tensor([raw_std]).view(1, 1, 1, 1)
                # 그레이스케일 단일채널 전처리
                img_gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                img_rs   = cv2.resize(img_gray, (28, 28), interpolation=cv2.INTER_LINEAR)
                t = torch.from_numpy(img_rs).float().div(255.0).unsqueeze(0).unsqueeze(0)
                tensor = (t - mean) / std
            else:
                tensor = _preprocess(crop)
        else:
            tensor = _preprocess(crop)

        with torch.no_grad():
            out = model(tensor)

        if classes:
            probs = torch.softmax(out[0] if out.dim() > 1 else out, dim=-1)
            pred_idx  = int(probs.argmax().item())
            pred_class = classes[pred_idx] if pred_idx < len(classes) else str(pred_idx)
            free_pass  = "40이상" in pred_class
            return {
                "age": None, "free_pass": free_pass, "is_adult": True,
                "model": "custom", "class": pred_class,
                "confidence": round(float(probs[pred_idx].item()), 3),
            }

        age = _parse_age_output(out)
        if age is None:
            return {"age": None, "free_pass": False, "is_adult": None, "model": "custom"}
        return {
            "age": round(age, 1), "free_pass": age >= 40,
            "is_adult": age >= 19, "model": "custom",
        }

    except Exception as e:
        logger.error(f"[FaceAge] 추론 실패: {e}")
        return {"age": None, "free_pass": False, "is_adult": None, "model": "custom"}


def _parse_age_output(out) -> Optional[float]:
    """모델 출력 형태에 따라 나이(float) 파싱"""
    if isinstance(out, torch.Tensor):
        if out.numel() == 1:
            return float(out.item())
        shape = out.shape
        if len(shape) == 2:
            if shape[1] == 1:
                return float(out[0, 0].item())
            # shape [1, N] — 클래스 분포로 해석
            probs = torch.softmax(out[0], dim=-1)
            n = probs.shape[0]
            ages = torch.arange(n, dtype=torch.float32)
            return float((probs * ages).sum().item())
    if isinstance(out, (list, tuple)):
        first = out[0]
        if isinstance(first, torch.Tensor):
            return _parse_age_output(first)
        return float(first)
    return None


# ── 신분증 위조 판별 ───────────────────────────────────────────

_id_verify_cache: Optional[tuple] = None

def get_id_verify_model():
    global _id_verify_cache
    if _id_verify_cache is None:
        p = _find_model_file("id_verify")
        if p:
            _id_verify_cache = _load_pt(p)
        if _id_verify_cache is None:
            logger.info("[IdVerify] 커스텀 모델 없음 — OCR 폴백 사용")
    return _id_verify_cache


def verify_id(img_bgr: np.ndarray) -> dict:
    """
    신분증 위조 판별 + 성인 여부

    Returns
    -------
    {
      'loaded'     : bool,           # 모델 로드 여부
      'is_real'    : bool | None,    # 진짜 신분증 여부 (None = 모델 없음)
      'confidence' : float,          # 0~1
      'is_adult'   : bool | None,    # 모델이 직접 제공하는 경우
      'model'      : 'custom' | 'none',
    }
    """
    model_tuple = get_id_verify_model()
    if model_tuple is None:
        return {"loaded": False, "is_real": None, "confidence": 0.0,
                "is_adult": None, "model": "none"}

    kind, model, _classes = model_tuple

    try:
        if kind == "yolo":
            results = model(img_bgr, verbose=False)
            probs = results[0].probs
            if probs is None:
                return {"loaded": True, "is_real": None, "confidence": 0.0,
                        "is_adult": None, "model": "custom"}
            # 클래스 0=fake, 1=real 가정
            real_conf = float(probs.data[1].item()) if probs.data.numel() > 1 \
                else float(probs.top1conf.item())
            return {
                "loaded": True,
                "is_real": real_conf >= 0.5,
                "confidence": round(real_conf, 3),
                "is_adult": None,
                "model": "custom",
            }

        tensor = _preprocess(img_bgr)
        with torch.no_grad():
            out = model(tensor)

        return _parse_id_output(out)

    except Exception as e:
        logger.error(f"[IdVerify] 추론 실패: {e}")
        return {"loaded": True, "is_real": None, "confidence": 0.0,
                "is_adult": None, "model": "custom"}


def _parse_id_output(out) -> dict:
    """모델 출력 형태에 따라 신분증 판별 결과 파싱"""
    base = {"loaded": True, "model": "custom"}

    # dict 출력 (가장 명시적)
    if isinstance(out, dict):
        is_real_raw = out.get("is_real", out.get("real", None))
        is_real = bool(is_real_raw >= 0.5) if isinstance(is_real_raw, (int, float)) \
                  else bool(is_real_raw)
        confidence = float(out.get("confidence", out.get("prob", 0.5)))
        is_adult_raw = out.get("is_adult", out.get("adult", None))
        is_adult = bool(is_adult_raw >= 0.5) if isinstance(is_adult_raw, (int, float)) \
                   else (bool(is_adult_raw) if is_adult_raw is not None else None)
        return {**base, "is_real": is_real, "confidence": round(confidence, 3),
                "is_adult": is_adult}

    # Tensor 출력
    if isinstance(out, torch.Tensor):
        out = out.squeeze()
        if out.numel() == 1:
            # 단일 스칼라 → sigmoid → real_prob
            real_conf = float(torch.sigmoid(out).item())
            return {**base, "is_real": real_conf >= 0.5,
                    "confidence": round(real_conf, 3), "is_adult": None}
        if out.numel() == 2:
            # [fake_logit, real_logit]
            probs = torch.softmax(out, dim=-1)
            real_conf = float(probs[1].item())
            return {**base, "is_real": real_conf >= 0.5,
                    "confidence": round(real_conf, 3), "is_adult": None}
        if out.numel() >= 3:
            # 예: [fake, real, is_adult] 형태
            probs = torch.softmax(out[:2], dim=-1)
            real_conf = float(probs[1].item())
            is_adult = bool(torch.sigmoid(out[2]).item() >= 0.5)
            return {**base, "is_real": real_conf >= 0.5,
                    "confidence": round(real_conf, 3), "is_adult": is_adult}

    # tuple/list 출력
    if isinstance(out, (list, tuple)):
        tensors = [o for o in out if isinstance(o, torch.Tensor)]
        if len(tensors) >= 2:
            real_conf = float(torch.sigmoid(tensors[0]).item())
            is_adult_conf = float(torch.sigmoid(tensors[1]).item())
            return {**base, "is_real": real_conf >= 0.5,
                    "confidence": round(real_conf, 3),
                    "is_adult": is_adult_conf >= 0.5}
        if len(tensors) == 1:
            return _parse_id_output(tensors[0])

    return {**base, "is_real": None, "confidence": 0.0, "is_adult": None}


# ── 모델 상태 확인 ─────────────────────────────────────────────

def model_status() -> dict:
    face_loaded = get_face_age_model() is not None
    id_loaded   = get_id_verify_model() is not None
    face_path   = _find_model_file("face_age")
    id_path     = _find_model_file("id_verify")
    return {
        "face_age_model": {
            "loaded": face_loaded,
            "path": str(face_path) if face_path else str(MODEL_DIR / "face_age.pt"),
            "exists": face_path is not None,
        },
        "id_verify_model": {
            "loaded": id_loaded,
            "path": str(id_path) if id_path else str(MODEL_DIR / "id_verify.pt"),
            "exists": id_path is not None,
        },
    }


def warmup_models():
    """서버 시작 시 모델 미리 로드"""
    get_face_age_model()
    get_id_verify_model()
