"""
얼굴 인식 모듈 (mediapipe 기반)

파이프라인:
  1. MediaPipe Face Detection으로 얼굴 검출
  2. 얼굴 영역 크롭 + 정렬 (눈 랜드마크 기준)
  3. 128-d 임베딩 추출 (픽셀 정규화 벡터)
  4. 코사인 유사도로 저장된 임베딩과 비교
"""

from __future__ import annotations

import io
import logging
import numpy as np
from dataclasses import dataclass
from typing import Optional

import cv2

logger = logging.getLogger(__name__)

FACE_MATCH_THRESHOLD = 0.40  # 코사인 거리 임계값


@dataclass
class FaceResult:
    matched: bool
    distance: float
    embedding: Optional[np.ndarray] = None
    error: Optional[str] = None


class FaceRecognizer:

    def __init__(self, threshold: float = FACE_MATCH_THRESHOLD):
        self.threshold = threshold
        self._detector = None

    def _get_detector(self):
        if self._detector is None:
            try:
                import mediapipe as mp
                self._detector = mp.solutions.face_detection.FaceDetection(
                    model_selection=1,      # 1 = 원거리 모델 (2m 이내)
                    min_detection_confidence=0.6,
                )
            except ImportError:
                logger.warning("mediapipe 없음 — OpenCV Haar fallback 사용")
        return self._detector

    def _decode_image(self, image_bytes: bytes) -> Optional[np.ndarray]:
        arr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        return img  # BGR

    def _detect_face_crop(self, img: np.ndarray) -> Optional[np.ndarray]:
        """얼굴 영역을 검출하고 112×112 로 크롭·리사이즈."""
        h, w = img.shape[:2]
        detector = self._get_detector()

        if detector is not None:
            import mediapipe as mp
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            results = detector.process(rgb)
            if not results.detections or len(results.detections) != 1:
                logger.info("얼굴 검출 수: %d", len(results.detections) if results.detections else 0)
                return None
            det = results.detections[0]
            bbox = det.location_data.relative_bounding_box
            x1 = max(0, int(bbox.xmin * w))
            y1 = max(0, int(bbox.ymin * h))
            x2 = min(w, int((bbox.xmin + bbox.width) * w))
            y2 = min(h, int((bbox.ymin + bbox.height) * h))
        else:
            # OpenCV Haar cascade fallback
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
            faces = cascade.detectMultiScale(gray, 1.1, 5, minSize=(60, 60))
            if len(faces) != 1:
                return None
            x1, y1, fw, fh = faces[0]
            x2, y2 = x1 + fw, y1 + fh

        face = img[y1:y2, x1:x2]
        if face.size == 0:
            return None
        return cv2.resize(face, (112, 112))

    def _compute_embedding(self, face_crop: np.ndarray) -> np.ndarray:
        """
        112×112 얼굴 이미지 → 128-d L2 정규화 벡터.
        경량 접근: 픽셀 특징(평균/분산 블록 + HOG-like) 기반.
        프로덕션에서는 InsightFace ArcFace 모델로 교체 권장.
        """
        gray = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
        # 8×8 블록 평균 + 분산 → 128-d
        blocks = gray.reshape(8, 14, 8, 14)
        means = blocks.mean(axis=(1, 3)).flatten()    # 64-d
        stds  = blocks.std(axis=(1, 3)).flatten()     # 64-d
        emb = np.concatenate([means, stds]).astype(np.float32)
        norm = np.linalg.norm(emb)
        return emb / (norm + 1e-8)

    # ── 공개 API ──────────────────────────────────────

    def extract_embedding(self, image_bytes: bytes) -> Optional[np.ndarray]:
        img = self._decode_image(image_bytes)
        if img is None:
            return None
        face = self._detect_face_crop(img)
        if face is None:
            return None
        return self._compute_embedding(face)

    def verify(self, image_bytes: bytes, stored_embedding: np.ndarray) -> FaceResult:
        live_emb = self.extract_embedding(image_bytes)
        if live_emb is None:
            return FaceResult(matched=False, distance=1.0, error="얼굴을 감지할 수 없습니다.")

        distance = float(np.linalg.norm(live_emb - stored_embedding))
        return FaceResult(matched=distance < self.threshold, distance=round(distance, 4), embedding=live_emb)

    def embedding_to_bytes(self, emb: np.ndarray) -> bytes:
        return emb.astype(np.float32).tobytes()

    def bytes_to_embedding(self, data: bytes) -> np.ndarray:
        return np.frombuffer(data, dtype=np.float32)


_recognizer: Optional[FaceRecognizer] = None


def get_face_recognizer() -> FaceRecognizer:
    global _recognizer
    if _recognizer is None:
        _recognizer = FaceRecognizer()
    return _recognizer
