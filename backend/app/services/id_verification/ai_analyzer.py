"""
신분증 위변조 판별 AI 모듈

3단계 분석 파이프라인:
  1. 텍스처 분석 — 프린팅 품질, 모아레 패턴, 주파수 도메인 이상 감지
  2. CNN 분류기 — EfficientNet-B0 fine-tuned (genuine vs forged)
  3. OCR 일관성 검증 — 텍스트 영역 추출 후 형식 규칙 검사
"""

from __future__ import annotations

import io
import re
import logging
from dataclasses import dataclass, field
from typing import Optional

import cv2
import numpy as np

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────
# 결과 데이터 클래스
# ─────────────────────────────────────────────

@dataclass
class IDAnalysisResult:
    is_genuine: bool
    confidence: float          # 0.0 ~ 1.0 (1.0 = 진짜 확신)
    id_type: str               # "주민등록증" | "운전면허증" | "여권" | "unknown"
    detail: dict = field(default_factory=dict)


# ─────────────────────────────────────────────
# 텍스처 분석기
# ─────────────────────────────────────────────

class TextureAnalyzer:
    """
    주파수 도메인(FFT) + LBP 텍스처로 인쇄 품질을 분석.
    위조 신분증은 일반 잉크젯/레이저 프린터로 제작되므로
    고주파 성분 분포와 텍스처 균일도가 정품과 다르다.
    """

    def analyze(self, img: np.ndarray) -> dict:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        scores = {
            "fft_score": self._fft_score(gray),
            "lbp_uniformity": self._lbp_uniformity(gray),
            "noise_level": self._noise_level(gray),
        }
        # 각 점수를 0~1로 정규화해서 진위 점수로 변환
        genuine_score = (
            scores["fft_score"] * 0.4
            + scores["lbp_uniformity"] * 0.4
            + (1 - scores["noise_level"]) * 0.2
        )
        return {"genuine_score": float(np.clip(genuine_score, 0, 1)), **scores}

    def _fft_score(self, gray: np.ndarray) -> float:
        f = np.fft.fft2(gray.astype(np.float32))
        fshift = np.fft.fftshift(f)
        magnitude = np.log1p(np.abs(fshift))
        h, w = magnitude.shape
        center = magnitude[h // 4: 3 * h // 4, w // 4: 3 * w // 4]
        # 정품 신분증은 중심 주파수 에너지 비율이 높음
        ratio = center.sum() / (magnitude.sum() + 1e-8)
        return float(np.clip(ratio * 2, 0, 1))

    def _lbp_uniformity(self, gray: np.ndarray) -> float:
        # 간단한 LBP 구현 (radius=1, 8 neighbors)
        rows, cols = gray.shape
        lbp = np.zeros_like(gray)
        for dy, dx in [(-1,-1),(-1,0),(-1,1),(0,1),(1,1),(1,0),(1,-1),(0,-1)]:
            shifted = np.roll(np.roll(gray, dy, axis=0), dx, axis=1)
            lbp = (lbp << 1) | (gray >= shifted).astype(np.uint8)
        hist, _ = np.histogram(lbp, bins=256, range=(0, 256))
        hist = hist / (hist.sum() + 1e-8)
        entropy = -np.sum(hist * np.log2(hist + 1e-8))
        # 엔트로피가 적절한 범위(4~6)이면 정품 패턴
        score = 1.0 - abs(entropy - 5.0) / 5.0
        return float(np.clip(score, 0, 1))

    def _noise_level(self, gray: np.ndarray) -> float:
        laplacian = cv2.Laplacian(gray, cv2.CV_64F)
        std = float(laplacian.std())
        # 노이즈가 너무 높으면 스캔본/복사본일 가능성
        return float(np.clip(std / 200.0, 0, 1))


# ─────────────────────────────────────────────
# CNN 분류기 (EfficientNet-B0 기반)
# ─────────────────────────────────────────────

class CNNClassifier:
    """
    EfficientNet-B0을 신분증 위변조 이진 분류로 fine-tune.
    모델 파일이 없으면 텍스처 분석 결과만으로 동작.
    """

    def __init__(self, model_path: Optional[str] = None):
        self._model = None
        self._transform = None
        if model_path:
            self._load_model(model_path)

    def _load_model(self, path: str):
        try:
            import torch
            import timm
            from torchvision import transforms

            self._model = timm.create_model("efficientnet_b0", pretrained=False, num_classes=2)
            state = torch.load(path, map_location="cpu")
            self._model.load_state_dict(state)
            self._model.eval()
            self._transform = transforms.Compose([
                transforms.Resize((224, 224)),
                transforms.ToTensor(),
                transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
            ])
            logger.info("CNN 모델 로드 완료: %s", path)
        except Exception as e:
            logger.warning("CNN 모델 로드 실패 (텍스처 분석만 사용): %s", e)

    def predict(self, img: np.ndarray) -> Optional[float]:
        if self._model is None:
            return None
        try:
            import torch
            from PIL import Image as PILImage

            pil = PILImage.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
            tensor = self._transform(pil).unsqueeze(0)
            with torch.no_grad():
                logits = self._model(tensor)
                prob = torch.softmax(logits, dim=1)[0][1].item()  # 진짜 클래스 확률
            return float(prob)
        except Exception as e:
            logger.error("CNN 추론 오류: %s", e)
            return None


# ─────────────────────────────────────────────
# OCR 일관성 검증
# ─────────────────────────────────────────────

class OCRConsistencyChecker:
    """easyocr로 텍스트를 추출하고 형식 규칙을 검사."""

    # 주민등록번호 패턴
    RRN_PATTERN = re.compile(r"\d{6}[-\s]\d{7}")
    # 운전면허번호 패턴
    DL_PATTERN = re.compile(r"\d{2}-\d{2}-\d{6}-\d{2}")
    # 발급일 패턴
    DATE_PATTERN = re.compile(r"(19|20)\d{2}[.\-년]\s?\d{1,2}[.\-월]\s?\d{1,2}")

    def __init__(self):
        self._reader = None

    def _get_reader(self):
        if self._reader is None:
            try:
                import easyocr
                self._reader = easyocr.Reader(["ko", "en"], gpu=False)
            except Exception as e:
                logger.warning("OCR 초기화 실패: %s", e)
        return self._reader

    def check(self, img: np.ndarray) -> dict:
        reader = self._get_reader()
        if reader is None:
            return {"ocr_available": False, "genuine_score": 0.5}

        try:
            results = reader.readtext(img, detail=0)
            text = " ".join(results)

            has_rrn = bool(self.RRN_PATTERN.search(text))
            has_dl = bool(self.DL_PATTERN.search(text))
            has_date = bool(self.DATE_PATTERN.search(text))

            id_type = "unknown"
            if has_rrn:
                id_type = "주민등록증"
            elif has_dl:
                id_type = "운전면허증"

            # 필수 패턴이 하나라도 있으면 형식 일관성 점수 부여
            score = 0.5
            if has_rrn or has_dl:
                score += 0.3
            if has_date:
                score += 0.2

            return {
                "ocr_available": True,
                "id_type": id_type,
                "has_rrn": has_rrn,
                "has_dl_number": has_dl,
                "has_issue_date": has_date,
                "genuine_score": float(np.clip(score, 0, 1)),
            }
        except Exception as e:
            logger.error("OCR 오류: %s", e)
            return {"ocr_available": False, "genuine_score": 0.5}


# ─────────────────────────────────────────────
# 통합 분석기
# ─────────────────────────────────────────────

class IDVerificationAnalyzer:
    """
    3단계 파이프라인을 실행하고 가중 합산으로 최종 판정.
    모델 가중치:
      - 텍스처:  35%
      - CNN:     45% (모델 없으면 텍스처에 재분배)
      - OCR:     20%
    """

    TEXTURE_W = 0.35
    CNN_W = 0.45
    OCR_W = 0.20

    def __init__(self, cnn_model_path: Optional[str] = None, threshold: float = 0.55):
        self.threshold = threshold
        self._texture = TextureAnalyzer()
        self._cnn = CNNClassifier(cnn_model_path)
        self._ocr = OCRConsistencyChecker()

    def analyze(self, img: np.ndarray) -> IDAnalysisResult:
        texture = self._texture.analyze(img)
        cnn_score = self._cnn.predict(img)
        ocr = self._ocr.check(img)

        t_score = texture["genuine_score"]
        o_score = ocr["genuine_score"]
        id_type = ocr.get("id_type", "unknown")

        # CNN 없을 때 OCR이 하드 게이트: 주민번호 또는 면허번호가 없으면 즉시 불합격
        if cnn_score is None:
            has_id_pattern = ocr.get("has_rrn") or ocr.get("has_dl_number")
            if not has_id_pattern:
                return IDAnalysisResult(
                    is_genuine=False,
                    confidence=0.1,
                    id_type=id_type,
                    detail={"texture": texture, "cnn_score": None, "ocr": ocr,
                            "threshold": self.threshold, "reject_reason": "신분증 번호 패턴 미감지"},
                )
            final = t_score * (self.TEXTURE_W + self.CNN_W * 0.6) + o_score * (self.OCR_W + self.CNN_W * 0.4)
        else:
            final = t_score * self.TEXTURE_W + cnn_score * self.CNN_W + o_score * self.OCR_W

        is_genuine = final >= self.threshold

        return IDAnalysisResult(
            is_genuine=is_genuine,
            confidence=round(float(final), 4),
            id_type=id_type,
            detail={
                "texture": texture,
                "cnn_score": cnn_score,
                "ocr": ocr,
                "threshold": self.threshold,
            },
        )


# 싱글톤 인스턴스 (앱 시작 시 1회 초기화)
_analyzer: Optional[IDVerificationAnalyzer] = None


def get_analyzer() -> IDVerificationAnalyzer:
    global _analyzer
    if _analyzer is None:
        import os
        model_path = os.environ.get("ID_VERIFY_MODEL_PATH")
        _analyzer = IDVerificationAnalyzer(cnn_model_path=model_path)
    return _analyzer
