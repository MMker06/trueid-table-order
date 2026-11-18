import cv2
import numpy as np
from typing import Tuple


ID_CARD_ASPECT = 1.585  # 85.6mm / 53.98mm (ISO/IEC 7810 ID-1)
TARGET_W, TARGET_H = 856, 540


def load_image(data: bytes) -> np.ndarray:
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("이미지를 디코딩할 수 없습니다.")
    return img


def normalize(img: np.ndarray) -> np.ndarray:
    """밝기·대비 정규화 (CLAHE)"""
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l = clahe.apply(l)
    return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)


def detect_and_crop_id(img: np.ndarray) -> Tuple[np.ndarray, bool]:
    """
    신분증 윤곽을 찾아 원근 보정(perspective warp) 후 크롭.
    신분증을 찾지 못하면 원본 이미지를 리사이즈해서 반환.
    """
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 50, 150)

    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:5]

    for cnt in contours:
        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
        if len(approx) == 4:
            pts = approx.reshape(4, 2).astype(np.float32)
            pts = _order_points(pts)
            warped = _four_point_transform(img, pts)
            h, w = warped.shape[:2]
            ratio = w / h
            if 1.3 < ratio < 1.9:
                return cv2.resize(warped, (TARGET_W, TARGET_H)), True

    return cv2.resize(img, (TARGET_W, TARGET_H)), False


def _order_points(pts: np.ndarray) -> np.ndarray:
    rect = np.zeros((4, 2), dtype=np.float32)
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def _four_point_transform(img: np.ndarray, pts: np.ndarray) -> np.ndarray:
    tl, tr, br, bl = pts
    w = int(max(np.linalg.norm(br - bl), np.linalg.norm(tr - tl)))
    h = int(max(np.linalg.norm(tr - br), np.linalg.norm(tl - bl)))
    dst = np.array([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype=np.float32)
    M = cv2.getPerspectiveTransform(pts, dst)
    return cv2.warpPerspective(img, M, (w, h))


def extract_roi_patches(img: np.ndarray) -> dict:
    """신분증 주요 영역 패치 추출 (사진, 홀로그램 예상 위치 등)"""
    h, w = img.shape[:2]
    return {
        "photo": img[int(h * 0.15):int(h * 0.85), int(w * 0.03):int(w * 0.28)],
        "hologram": img[int(h * 0.5):int(h * 0.95), int(w * 0.65):int(w * 0.98)],
        "text_zone": img[int(h * 0.15):int(h * 0.85), int(w * 0.30):int(w * 0.98)],
        "full": img,
    }
