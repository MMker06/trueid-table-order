"""
MINCERT — 자체 서명 성인인증 QR 프로토콜
실제 PASS 앱 / 모바일 신분증 QR과 동일한 원리:
  QR = "MINCERT:" + JWT(HS256, 생년월일 포함, 5분 유효)
편의점 POS가 PASS QR을 검증하는 방식과 구조 동일.
실 서비스 전환 시 서명 키만 PASS/행안부 공개키로 교체하면 됨.
"""
import os
import secrets
from datetime import date, datetime, timezone
from typing import Optional

from jose import jwt, JWTError

_ALGORITHM = "HS256"
_ISSUER = "trueid-cert"
_TTL = 300  # 5분


def _secret() -> str:
    """QR 서명 키. 환경변수 CERT_QR_SECRET 필수 — 기본값 없음.

    기본값을 두면 키를 설정하지 않은 서버가 전부 같은 키로 서명하게 되어
    누구나 성인 인증 QR을 위조할 수 있으므로, 미설정 시 바로 에러를 낸다.
    """
    value = os.getenv("CERT_QR_SECRET", "")
    if not value:
        raise RuntimeError(
            "CERT_QR_SECRET 환경변수가 설정되지 않았습니다. "
            "python scripts/gen_secret.py 로 생성해 .env 에 넣어 주세요."
        )
    return value


def generate(birth_date: str, name: str = "본인") -> str:
    """
    birth_date: YYYY-MM-DD
    반환: QR에 인코딩할 문자열 (MINCERT: 접두어 포함)
    """
    now = int(datetime.now(tz=timezone.utc).timestamp())
    payload = {
        "iss": _ISSUER,
        "sub": "age_verify",
        "iat": now,
        "exp": now + _TTL,
        "birth": birth_date.replace("-", ""),  # YYYYMMDD
        "nonce": secrets.token_hex(6),
    }
    token = jwt.encode(payload, _secret(), algorithm=_ALGORITHM)
    return f"MINCERT:{token}"


def verify(qr_data: str) -> dict:
    """
    반환:
      valid (bool), is_adult (bool), age (int), birth_date (str), error (str|None)
    """
    if not qr_data.startswith("MINCERT:"):
        return {"valid": False, "is_adult": False, "age": 0,
                "birth_date": None, "error": "MINCERT 형식이 아닙니다"}

    token = qr_data[len("MINCERT:"):]
    try:
        payload = jwt.decode(token, _secret(), algorithms=[_ALGORITHM],
                             issuer=_ISSUER,
                             options={"verify_exp": True})
    except JWTError as e:
        msg = str(e)
        if "expired" in msg.lower():
            return {"valid": False, "is_adult": False, "age": 0,
                    "birth_date": None, "error": "QR 유효시간 만료 (5분)"}
        return {"valid": False, "is_adult": False, "age": 0,
                "birth_date": None, "error": f"QR 서명 검증 실패: {msg}"}

    birth_raw = payload.get("birth", "")
    if len(birth_raw) != 8:
        return {"valid": False, "is_adult": False, "age": 0,
                "birth_date": None, "error": "생년월일 형식 오류"}

    try:
        by, bm, bd = int(birth_raw[:4]), int(birth_raw[4:6]), int(birth_raw[6:])
        today = date.today()
        age = today.year - by - ((today.month, today.day) < (bm, bd))
        is_adult = age >= 19
        birth_str = f"{by}-{bm:02d}-{bd:02d}"
        return {
            "valid": True,
            "is_adult": is_adult,
            "age": age,
            "birth_date": birth_str,
            "error": None if is_adult else f"미성년자 (만 {age}세) — 인증 거부",
        }
    except ValueError:
        return {"valid": False, "is_adult": False, "age": 0,
                "birth_date": None, "error": "생년월일 파싱 오류"}
