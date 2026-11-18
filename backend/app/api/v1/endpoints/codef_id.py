"""
CODEF 행정안전부 신분증 진위확인 API 연동
- OAuth2 client_credentials 토큰 자동 관리
- 주민번호 RSA 암호화 (CODEF 공개키)
- 진위 확인 + 나이 계산 → 성인 여부 반환
- 주민번호는 서버에 절대 저장하지 않음

codef.io 가입 → 데모 서비스 신청 → .env에 키 추가하면 바로 동작
"""
import os
import base64
import httpx
import logging
from datetime import date, datetime, timedelta
from typing import Optional

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend

logger = logging.getLogger(__name__)

# ── 환경변수 ──────────────────────────────────────────────
CODEF_CLIENT_ID = os.getenv("CODEF_CLIENT_ID", "")
CODEF_CLIENT_SECRET = os.getenv("CODEF_CLIENT_SECRET", "")
CODEF_MODE = os.getenv("CODEF_MODE", "demo")  # "demo" | "prod"

OAUTH_URL = "https://oauth.codef.io/oauth/token"
API_BASE = "https://development.codef.io" if CODEF_MODE == "demo" else "https://api.codef.io"
ID_CHECK_PATH = "/v1/kr/public/mw/check-identity-card"

# ── 토큰 캐시 ─────────────────────────────────────────────
_token_cache: dict = {"token": None, "expires_at": datetime.min}


async def _get_access_token() -> str:
    global _token_cache
    if _token_cache["token"] and datetime.utcnow() < _token_cache["expires_at"]:
        return _token_cache["token"]

    if not CODEF_CLIENT_ID or not CODEF_CLIENT_SECRET:
        raise RuntimeError("CODEF_CLIENT_ID / CODEF_CLIENT_SECRET 환경변수를 설정하세요 (codef.io 데모 신청)")

    async with httpx.AsyncClient() as client:
        r = await client.post(
            OAUTH_URL,
            data={"grant_type": "client_credentials", "scope": "read"},
            auth=(CODEF_CLIENT_ID, CODEF_CLIENT_SECRET),
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()

    token = data["access_token"]
    expires_in = int(data.get("expires_in", 604800))
    _token_cache = {
        "token": token,
        "expires_at": datetime.utcnow() + timedelta(seconds=expires_in - 60),
    }
    return token


async def _get_codef_pubkey() -> str:
    """CODEF RSA 공개키 취득"""
    token = await _get_access_token()
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{API_BASE}/v1/public/key",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
        r.raise_for_status()
        return r.json()["publicKey"]


def _rsa_encrypt(plain: str, pem_b64: str) -> str:
    """CODEF 공개키로 RSA/OAEP 암호화 → base64 반환"""
    pem_bytes = base64.b64decode(pem_b64)
    public_key = serialization.load_der_public_key(pem_bytes, backend=default_backend())
    encrypted = public_key.encrypt(
        plain.encode("utf-8"),
        padding.OAEP(
            mgf=padding.MGF1(algorithm=hashes.SHA1()),
            algorithm=hashes.SHA1(),
            label=None,
        ),
    )
    return base64.b64encode(encrypted).decode("utf-8")


def _calc_age(jumin_front: str) -> int:
    """주민번호 앞 6자리(YYMMDD) + 뒷자리 첫째(성별코드)로 나이 계산"""
    yy = int(jumin_front[:2])
    mm = int(jumin_front[2:4])
    dd = int(jumin_front[4:6])
    # 성별코드: 1/2 = 1900년대, 3/4 = 2000년대, 9/0 = 1800년대
    # 뒷자리 없이 앞 2자리만으로: 00-23 → 2000년대, 24-99 → 1900년대
    if yy <= (date.today().year % 100):
        year = 2000 + yy
    else:
        year = 1900 + yy
    today = date.today()
    age = today.year - year - ((today.month, today.day) < (mm, dd))
    return age


async def verify_id_card(
    name: str,
    jumin_front: str,   # 주민번호 앞 6자리 (YYMMDD)
    jumin_back: str,    # 주민번호 뒤 7자리
    issue_date: str,    # 발급일자 YYYYMMDD
) -> dict:
    """
    행정안전부 신분증 진위확인 + 성인 여부 반환.
    주민번호는 암호화 후 전송, 서버에 저장 안 함.
    반환: {authentic, is_adult, age, error}
    """
    if not CODEF_CLIENT_ID:
        return {
            "authentic": False, "is_adult": False, "age": 0,
            "error": "CODEF API 키 미설정 (codef.io 데모 신청 후 .env에 추가)"
        }

    try:
        token = await _get_access_token()
        pubkey = await _get_codef_pubkey()

        jumin_full = jumin_front + jumin_back
        encrypted_jumin = _rsa_encrypt(jumin_full, pubkey)

        payload = {
            "organization": "0002",   # 행정안전부
            "loginType": "0",
            "loginTypeLevel": "1",
            "userName": name,
            "identity": encrypted_jumin,
            "issueDate": issue_date,
        }

        async with httpx.AsyncClient() as client:
            r = await client.post(
                f"{API_BASE}{ID_CHECK_PATH}",
                json=payload,
                headers={"Authorization": f"Bearer {token}"},
                timeout=15,
            )

        resp = r.json()
        result_code = resp.get("result", {}).get("code", "")
        data = resp.get("data", {})

        if result_code != "CF-00000":
            msg = resp.get("result", {}).get("message", "API 오류")
            return {"authentic": False, "is_adult": False, "age": 0, "error": f"CODEF 오류: {msg}"}

        authenticity = str(data.get("resAuthenticity", "0"))
        if authenticity != "1":
            return {
                "authentic": False, "is_adult": False, "age": 0,
                "error": "신분증 진위 확인 실패 — 위변조 또는 존재하지 않는 신분증"
            }

        # 진짜 신분증 → 나이 계산
        age = _calc_age(jumin_front)
        is_adult = age >= 19

        logger.info(f"신분증 인증 완료: 나이={age}, 성인={is_adult}")

        return {
            "authentic": True,
            "is_adult": is_adult,
            "age": age,
            "error": None if is_adult else f"미성년자 (만 {age}세) — 성인 전용 상품 주문 불가",
        }

    except httpx.HTTPStatusError as e:
        return {"authentic": False, "is_adult": False, "age": 0, "error": f"HTTP 오류: {e.response.status_code}"}
    except Exception as e:
        logger.exception("신분증 진위확인 오류")
        return {"authentic": False, "is_adult": False, "age": 0, "error": f"서버 오류: {str(e)}"}
