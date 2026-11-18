"""
신분증 OCR — EasyOCR로 주민번호 앞 6자리 추출 후 나이 계산
외부 API 없음, 즉시 사용 가능
지원: 주민등록증, 운전면허증, 여권
"""
import re
import logging
import threading
import numpy as np
from datetime import date

logger = logging.getLogger(__name__)

# EasyOCR Reader — 첫 로드 시 모델 다운로드 (약 30초), 이후 메모리 상주
_reader = None
_reader_lock = threading.Lock()


def _get_reader():
    global _reader
    if _reader is None:
        with _reader_lock:
            if _reader is None:
                import easyocr
                logger.info("EasyOCR 모델 로딩 중...")
                _reader = easyocr.Reader(['ko', 'en'], gpu=False, verbose=False)
                logger.info("EasyOCR 준비 완료")
    return _reader


def _calc_age(yy: int, mm: int, dd: int, century_hint: int = None) -> int:
    """YY MM DD → 나이 계산. century_hint: 1900 or 2000"""
    cur_yy = date.today().year % 100
    if century_hint:
        year = century_hint + yy
    elif yy <= cur_yy:
        year = 2000 + yy
    else:
        year = 1900 + yy
    today = date.today()
    return today.year - year - ((today.month, today.day) < (mm, dd))


def _preprocess(img: np.ndarray) -> np.ndarray:
    import cv2
    # 대비 강화 + 선명화
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    _, thresh = cv2.threshold(enhanced, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    return thresh


def extract_age_from_id(img: np.ndarray) -> dict:
    """
    신분증 이미지 → 나이 추출.
    반환: {found, age, is_adult, method, raw_text}
    """
    reader = _get_reader()

    # 원본 + 전처리본 둘 다 시도 (인식률 향상)
    results_orig = reader.readtext(img, detail=1, paragraph=False)
    proc = _preprocess(img)
    results_proc = reader.readtext(proc, detail=1, paragraph=False)

    # 신뢰도 0.3 이상 텍스트만 수집
    texts = []
    for _, text, conf in results_orig + results_proc:
        if conf >= 0.3:
            texts.append(text.strip())

    full = ' '.join(texts)
    compact = re.sub(r'\s+', '', full)

    logger.info(f"OCR 인식 텍스트: {full[:200]}")

    # ── 1. 주민등록번호 패턴: XXXXXX-XXXXXXX ──
    jumin = re.search(r'(\d{6})\s*[-—–]\s*(\d{7})', full)
    if not jumin:
        jumin = re.search(r'(\d{6})[-—–](\d{7})', compact)
    if jumin:
        front = jumin.group(1)
        back_first = jumin.group(2)[0]
        # 뒷자리 첫째: 1/2=1900s, 3/4=2000s
        century = 2000 if back_first in ('3', '4') else 1900
        yy, mm, dd = int(front[:2]), int(front[2:4]), int(front[4:6])
        try:
            age = _calc_age(yy, mm, dd, century)
            return {'found': True, 'age': age, 'is_adult': age >= 19,
                    'method': '주민등록번호', 'raw': f"{front}-{jumin.group(2)[0]}******"}
        except ValueError:
            pass

    # ── 2. 주민번호 앞 6자리만 있는 경우 (뒷자리 가림) ──
    jumin_front_only = re.search(r'(\d{6})\s*[-—–]', full)
    if jumin_front_only:
        front = jumin_front_only.group(1)
        yy, mm, dd = int(front[:2]), int(front[2:4]), int(front[4:6])
        try:
            age = _calc_age(yy, mm, dd)
            return {'found': True, 'age': age, 'is_adult': age >= 19,
                    'method': '주민번호 앞자리', 'raw': f"{front}-*******"}
        except ValueError:
            pass

    # ── 3. 운전면허증: 생년월일 YYYY.MM.DD / YYYY-MM-DD ──
    birthday = re.search(r'(19|20)(\d{2})[.\-/](\d{1,2})[.\-/](\d{1,2})', full)
    if birthday:
        year = int(birthday.group(1) + birthday.group(2))
        mm, dd = int(birthday.group(3)), int(birthday.group(4))
        today = date.today()
        age = today.year - year - ((today.month, today.day) < (mm, dd))
        return {'found': True, 'age': age, 'is_adult': age >= 19,
                'method': '생년월일', 'raw': f"{year}.{mm:02d}.{dd:02d}"}

    # ── 4. 여권 MRZ: 하단 기계판독 영역 YYMMDD ──
    mrz = re.search(r'[A-Z<]{5,}(\d{6})[0-9<]', compact)
    if mrz:
        front = mrz.group(1)
        yy, mm, dd = int(front[:2]), int(front[2:4]), int(front[4:6])
        try:
            age = _calc_age(yy, mm, dd)
            return {'found': True, 'age': age, 'is_adult': age >= 19,
                    'method': '여권 MRZ', 'raw': front}
        except ValueError:
            pass

    return {'found': False, 'age': 0, 'is_adult': False,
            'method': None, 'raw': full[:100]}
