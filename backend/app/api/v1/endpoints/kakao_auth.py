"""
카카오 OAuth 성인인증
사용자가 카카오 로그인 → 생년월일 가져와서 만 19세 이상 확인
주민번호 불필요, 카카오에 생년 등록된 계정이면 즉시 동작
"""
import os
import base64
import httpx
from datetime import date
from urllib.parse import quote

KAKAO_REST_KEY = os.getenv("KAKAO_REST_API_KEY", "")
KAKAO_CLIENT_SECRET = os.getenv("KAKAO_CLIENT_SECRET", "")
KAKAO_REDIRECT_URI = os.getenv(
    "KAKAO_REDIRECT_URI",
    "http://localhost:8000/api/v1/orders/kakao-callback",
)
AUTHORIZE_URL = "https://kauth.kakao.com/oauth/authorize"
TOKEN_URL = "https://kauth.kakao.com/oauth/token"
USERINFO_URL = "https://kapi.kakao.com/v2/user/me"


def make_authorize_url(order_id: str, token: str) -> str:
    # base64 padding(==) 은 URL 쿼리에서 오작동 — rstrip으로 제거
    state = base64.urlsafe_b64encode(f"{order_id}:{token}".encode()).decode().rstrip("=")
    params = (
        f"?client_id={KAKAO_REST_KEY}"
        f"&redirect_uri={quote(KAKAO_REDIRECT_URI, safe='')}"
        f"&response_type=code"
        f"&scope=birthyear,birthday"
        f"&state={state}"
    )
    return AUTHORIZE_URL + params


def is_configured() -> bool:
    return bool(KAKAO_REST_KEY)


async def exchange_code(code: str) -> dict:
    """인가 코드 → 액세스 토큰"""
    data = {
        "grant_type": "authorization_code",
        "client_id": KAKAO_REST_KEY,
        "redirect_uri": KAKAO_REDIRECT_URI,
        "code": code,
    }
    if KAKAO_CLIENT_SECRET:
        data["client_secret"] = KAKAO_CLIENT_SECRET
    async with httpx.AsyncClient() as client:
        r = await client.post(TOKEN_URL, data=data, timeout=10)
        r.raise_for_status()
        return r.json()


async def get_user_info(access_token: str) -> dict:
    """카카오 사용자 정보 조회"""
    async with httpx.AsyncClient() as client:
        r = await client.get(USERINFO_URL, headers={
            "Authorization": f"Bearer {access_token}",
        }, timeout=10)
        r.raise_for_status()
        return r.json()


def extract_age(user_info: dict) -> tuple[int | None, str | None]:
    """
    카카오 유저 정보에서 나이 추출.
    반환: (age, error_message)
    """
    account = user_info.get("kakao_account", {})
    birthyear = account.get("birthyear")  # "1990"
    birthday = account.get("birthday")    # "0115" (MMDD)

    if not birthyear:
        return None, "카카오 계정에 출생연도가 등록되어 있지 않습니다.\n카카오 계정 설정에서 생년월일을 등록해 주세요."

    year = int(birthyear)
    today = date.today()

    if birthday:
        mm, dd = int(birthday[:2]), int(birthday[2:])
        age = today.year - year - ((today.month, today.day) < (mm, dd))
    else:
        # 생일 없으면 연도만으로 보수적 계산
        age = today.year - year - 1

    return age, None
