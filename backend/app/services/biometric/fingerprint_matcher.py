"""
지문 인식 모듈

테이블 오더 단말기의 지문 센서 SDK(FutureTech, Suprema 등)에서
ISO/IEC 19794-2 형식의 특징점(minutiae) 템플릿을 전달받아 비교.

실제 센서가 없는 환경에서는 OpenCV ORB 기반의 소프트웨어 매처로 동작.
"""

from __future__ import annotations

import hashlib
import logging
import numpy as np
from dataclasses import dataclass
from typing import Optional

logger = logging.getLogger(__name__)

FINGERPRINT_SCORE_THRESHOLD = 40  # ORB 매처 기준 매칭 포인트 수


@dataclass
class FingerprintResult:
    matched: bool
    score: int            # 매칭된 특징점 수
    error: Optional[str] = None


class FingerprintMatcher:
    """
    두 가지 모드:
    - SDK 모드: 하드웨어 SDK가 반환하는 매칭 점수(int)를 그대로 사용
    - 소프트웨어 모드: 지문 이미지 바이트에서 ORB 특징점 추출 후 BFMatcher 비교
    """

    def __init__(self, threshold: int = FINGERPRINT_SCORE_THRESHOLD):
        self.threshold = threshold

    # ── 등록 ──────────────────────────────────────────
    def extract_template(self, fingerprint_image_bytes: bytes) -> Optional[bytes]:
        """지문 이미지에서 ORB 특징점 디스크립터를 추출해 직렬화."""
        try:
            import cv2
            arr = np.frombuffer(fingerprint_image_bytes, np.uint8)
            img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
            if img is None:
                return None
            img = cv2.equalizeHist(img)
            orb = cv2.ORB_create(nfeatures=500)
            kps, descs = orb.detectAndCompute(img, None)
            if descs is None or len(descs) < 10:
                return None
            # 디스크립터를 바이트로 직렬화
            return descs.astype(np.uint8).tobytes()
        except Exception as e:
            logger.error("지문 템플릿 추출 오류: %s", e)
            return None

    # ── SDK 모드 (단말기 연동 시 사용) ─────────────────
    def verify_with_sdk_score(self, sdk_score: int) -> FingerprintResult:
        """하드웨어 SDK가 반환한 점수로 판정."""
        matched = sdk_score >= self.threshold
        return FingerprintResult(matched=matched, score=sdk_score)

    # ── 소프트웨어 모드 ────────────────────────────────
    def verify(self, live_image_bytes: bytes, stored_template_bytes: bytes) -> FingerprintResult:
        try:
            import cv2
            arr = np.frombuffer(live_image_bytes, np.uint8)
            live_img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
            if live_img is None:
                return FingerprintResult(matched=False, score=0, error="이미지 디코딩 실패")

            live_img = cv2.equalizeHist(live_img)
            orb = cv2.ORB_create(nfeatures=500)
            _, live_descs = orb.detectAndCompute(live_img, None)
            if live_descs is None:
                return FingerprintResult(matched=False, score=0, error="특징점 추출 실패")

            stored_descs = np.frombuffer(stored_template_bytes, dtype=np.uint8).reshape(-1, 32)
            matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
            matches = matcher.match(live_descs, stored_descs)
            good = [m for m in matches if m.distance < 60]
            score = len(good)
            return FingerprintResult(matched=score >= self.threshold, score=score)
        except Exception as e:
            logger.error("지문 매칭 오류: %s", e)
            return FingerprintResult(matched=False, score=0, error=str(e))

    def template_to_bytes(self, template: bytes) -> bytes:
        return template

    def bytes_to_template(self, data: bytes) -> bytes:
        return data


_matcher: Optional[FingerprintMatcher] = None


def get_fingerprint_matcher() -> FingerprintMatcher:
    global _matcher
    if _matcher is None:
        _matcher = FingerprintMatcher()
    return _matcher
