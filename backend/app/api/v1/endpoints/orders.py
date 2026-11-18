import hashlib
import secrets
import socket
from uuid import UUID
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List, Optional
from ....core.database import get_db
from ....models.order import TableOrder, OrderItem, OrderVerification, OrderStatus, MobileVerifyToken
from ....models.merchant import Merchant
from ....models.menu import MenuItem
from ..endpoints.auth import get_current_user
from ....models.user import User


def _get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '127.0.0.1'

router = APIRouter(prefix="/orders", tags=["주문"])


class CartItem(BaseModel):
    menu_item_id: str
    name: str
    price: int
    quantity: int
    is_adult_only: bool = False

class OrderCreate(BaseModel):
    merchant_id: str
    table_number: str
    items: List[CartItem]
    adult_count: int = 0          # AI/수동으로 감지된 성인 수
    ai_adult_verified: bool = False  # AI가 전원 25세 이상 확인 → 카카오 인증 면제

class VerifyQR(BaseModel):
    qr_data: str

class VerifyIdCard(BaseModel):
    name: str
    jumin_front: str   # 주민번호 앞 6자리
    jumin_back: str    # 주민번호 뒤 7자리
    issue_date: str    # 발급일자 YYYYMMDD


def _get_merchant_by_id(merchant_id: str, db: Session) -> Merchant:
    m = db.query(Merchant).filter(Merchant.id == merchant_id).first()
    if not m:
        raise HTTPException(404, "매장을 찾을 수 없습니다.")
    return m


@router.post("", status_code=201)
def create_order(body: OrderCreate, db: Session = Depends(get_db)):
    """테이블에서 주문 생성 — 고객 인증 불필요"""
    m = _get_merchant_by_id(body.merchant_id, db)
    has_adult = any(i.is_adult_only for i in body.items)
    total = sum(i.price * i.quantity for i in body.items)

    # AI가 전원 성인 확인 → 주류 있어도 카카오 인증 생략
    needs_verify = has_adult and not body.ai_adult_verified

    order = TableOrder(
        merchant_id=m.id,
        table_number=body.table_number,
        total_amount=total,
        requires_adult_verify=needs_verify,
        adult_verify_count=body.adult_count if needs_verify else 0,
        status=OrderStatus.PENDING_VERIFY if needs_verify else OrderStatus.CONFIRMED,
    )
    db.add(order)
    db.flush()

    for ci in body.items:
        db.add(OrderItem(
            order_id=order.id,
            menu_item_id=ci.menu_item_id if ci.menu_item_id else None,
            name=ci.name,
            price=ci.price,
            quantity=ci.quantity,
            is_adult_only=ci.is_adult_only,
        ))
    db.commit()
    db.refresh(order)
    return _order_dict(order)


@router.post("/{order_id}/verify-qr")
def verify_qr(order_id: UUID, body: VerifyQR, db: Session = Depends(get_db)):
    """QR 1개 인증 처리 — MINCERT 서명 검증 포함"""
    from .cert_qr import verify as verify_cert

    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    if not order:
        raise HTTPException(404, "주문을 찾을 수 없습니다.")
    if order.status != OrderStatus.PENDING_VERIFY:
        raise HTTPException(400, "인증이 필요하지 않은 주문입니다.")

    # ── MINCERT QR: 서명 검증 + 나이 확인 ──
    if body.qr_data.startswith("MINCERT:"):
        result = verify_cert(body.qr_data)
        if not result["valid"]:
            raise HTTPException(400, result["error"])
        if not result["is_adult"]:
            raise HTTPException(400, result["error"])  # 미성년자 거부
        # 검증 통과 — 해시는 exp+nonce 포함되어 있어 재사용 불가
    # ── 일반 QR: 형식 무관, 재사용만 방지 ──

    qr_hash = hashlib.sha256(body.qr_data.encode()).hexdigest()
    dup = db.query(OrderVerification).filter(
        OrderVerification.order_id == order_id,
        OrderVerification.qr_hash == qr_hash,
    ).first()
    if dup:
        raise HTTPException(400, "이미 사용된 QR 코드입니다.")

    db.add(OrderVerification(order_id=order.id, qr_hash=qr_hash))
    order.adult_verified_count += 1

    if order.adult_verified_count >= order.adult_verify_count:
        order.status = OrderStatus.CONFIRMED

    db.commit()
    db.refresh(order)
    return {
        "verified_count": order.adult_verified_count,
        "required_count": order.adult_verify_count,
        "completed": order.status == OrderStatus.CONFIRMED,
    }


@router.get("/kitchen/{merchant_id}")
def kitchen_orders(merchant_id: UUID, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """주방/카운터용 주문 목록"""
    orders = db.query(TableOrder).filter(
        TableOrder.merchant_id == merchant_id,
        TableOrder.status.in_([OrderStatus.CONFIRMED, OrderStatus.PREPARING, OrderStatus.READY]),
    ).order_by(TableOrder.created_at).all()
    return [_order_dict(o) for o in orders]


@router.patch("/{order_id}/status")
def update_status(order_id: UUID, status: OrderStatus, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    if not order:
        raise HTTPException(404, "주문을 찾을 수 없습니다.")
    order.status = status
    order.updated_at = datetime.utcnow()
    db.commit()
    return _order_dict(order)


class MobileVerifyRequest(BaseModel):
    base_url: Optional[str] = None   # 클라이언트가 알고 있는 API 베이스 URL


@router.post("/{order_id}/mobile-verify/request")
def request_mobile_verify(order_id: UUID, body: MobileVerifyRequest = None, db: Session = Depends(get_db)):
    """태블릿에 표시할 QR 인증 토큰 발급"""
    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    if not order:
        raise HTTPException(404, "주문을 찾을 수 없습니다.")
    if order.status != OrderStatus.PENDING_VERIFY:
        raise HTTPException(400, "인증이 필요하지 않은 주문입니다.")

    token = secrets.token_urlsafe(32)
    expires = datetime.utcnow() + timedelta(minutes=10)
    db.add(MobileVerifyToken(order_id=order.id, token=token, expires_at=expires))
    db.commit()

    # 클라이언트가 base_url을 전달하면 그것을 사용 (네트워크 접근성 보장)
    if body and body.base_url:
        api_base = body.base_url.rstrip('/')
    else:
        ip = _get_local_ip()
        api_base = f"http://{ip}:8000/api/v1"
    verify_url = f"{api_base}/orders/{order_id}/mobile-verify/{token}/page"
    return {"token": token, "verify_url": verify_url, "expires_in": 600}


@router.get("/{order_id}/mobile-verify/{token}/page", response_class=HTMLResponse)
def mobile_verify_page(order_id: UUID, token: str, db: Session = Depends(get_db)):
    """고객 스마트폰에서 열리는 성인 확인 페이지"""
    mv = db.query(MobileVerifyToken).filter(
        MobileVerifyToken.order_id == order_id,
        MobileVerifyToken.token == token,
    ).first()

    def _error_page(msg: str) -> str:
        return f"""<!DOCTYPE html><html lang="ko"><head><meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>오류</title>
        <style>body{{font-family:-apple-system,sans-serif;display:flex;align-items:center;
        justify-content:center;min-height:100vh;background:#f5f5f5;margin:0}}
        .card{{background:#fff;border-radius:16px;padding:40px 32px;text-align:center;
        max-width:360px;width:90%;box-shadow:0 4px 24px rgba(0,0,0,.08)}}
        h2{{color:#e53935;margin-top:12px}}</style></head>
        <body><div class="card"><div style="font-size:48px">⚠️</div>
        <h2>{msg}</h2></div></body></html>"""

    if not mv:
        return HTMLResponse(_error_page("유효하지 않은 인증 링크"), status_code=404)
    if mv.used:
        return HTMLResponse(_error_page("이미 사용된 인증입니다"), status_code=400)
    if datetime.utcnow() > mv.expires_at:
        return HTMLResponse(_error_page("인증 링크가 만료되었습니다"), status_code=400)

    kakao_url = f"/api/v1/orders/{order_id}/mobile-verify/{token}/kakao-start"
    return HTMLResponse(f"""<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>성인 인증</title>
  <style>
    *{{margin:0;padding:0;box-sizing:border-box}}
    body{{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
      background:linear-gradient(135deg,#0064d2 0%,#1a3a8f 100%);
      min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}}
    .card{{background:#fff;border-radius:20px;padding:40px 28px;
      max-width:380px;width:100%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,.25)}}
    .badge{{display:inline-flex;align-items:center;gap:8px;
      background:#e8f0fe;color:#0064d2;border-radius:20px;
      padding:6px 16px;font-size:13px;font-weight:700;margin-bottom:20px}}
    .icon{{font-size:52px;margin-bottom:16px}}
    h1{{font-size:20px;font-weight:800;color:#1a1a1a;margin-bottom:10px}}
    p{{color:#666;font-size:13px;line-height:1.7;margin-bottom:28px}}
    .kakao-btn{{display:flex;align-items:center;justify-content:center;gap:10px;
      background:#FEE500;color:#191919;border:none;border-radius:14px;
      padding:17px;width:100%;font-size:16px;font-weight:700;cursor:pointer;
      text-decoration:none;transition:opacity .15s}}
    .kakao-btn:active{{opacity:.8}}
    .notice{{margin-top:20px;font-size:11px;color:#aaa;line-height:1.6}}
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">🪪 성인 인증</div>
    <div class="icon">🔞</div>
    <h1>성인 여부 확인</h1>
    <p>주문하신 메뉴에 성인 전용 상품이 포함되어 있습니다.<br>카카오 계정으로 만 19세 이상임을 확인합니다.</p>
    <a class="kakao-btn" href="{kakao_url}">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="#191919">
        <path d="M12 3C6.477 3 2 6.477 2 10.8c0 2.7 1.7 5.1 4.3 6.6l-.9 3.3c-.1.3.3.6.6.4l3.9-2.5c.7.1 1.4.1 2.1.1 5.5 0 10-3.5 10-7.8S17.5 3 12 3z"/>
      </svg>
      카카오로 성인 인증
    </a>
    <p class="notice">카카오 계정에 등록된 생년월일로 나이를 확인합니다<br>만 19세 미만은 인증이 거부됩니다</p>
  </div>
</body>
</html>""")


@router.post("/{order_id}/mobile-verify/{token}/confirm")
def confirm_mobile_verify(order_id: UUID, token: str, db: Session = Depends(get_db)):
    """고객 폰에서 확인 버튼 클릭 → 인증 1건 처리"""
    mv = db.query(MobileVerifyToken).filter(
        MobileVerifyToken.order_id == order_id,
        MobileVerifyToken.token == token,
    ).first()

    if not mv:
        raise HTTPException(404, "유효하지 않은 토큰입니다.")
    if mv.used:
        raise HTTPException(400, "이미 사용된 인증입니다.")
    if datetime.utcnow() > mv.expires_at:
        raise HTTPException(400, "인증 링크가 만료되었습니다.")

    mv.used = True
    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    order.adult_verified_count += 1
    if order.adult_verified_count >= order.adult_verify_count:
        order.status = OrderStatus.CONFIRMED

    db.commit()
    return {"success": True, "message": "인증 완료", "remaining": max(0, order.adult_verify_count - order.adult_verified_count)}


@router.post("/{order_id}/verify-id-ocr")
async def verify_id_ocr(
    order_id: UUID,
    image: __import__('fastapi').UploadFile = __import__('fastapi').File(...),
    db: Session = Depends(get_db),
):
    """신분증 사진 OCR → 나이 확인 → 성인 인증"""
    from .ocr_id import extract_age_from_id
    import cv2, numpy as np

    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    if not order:
        raise HTTPException(404, "주문을 찾을 수 없습니다.")
    if order.status != OrderStatus.PENDING_VERIFY:
        raise HTTPException(400, "인증이 필요하지 않은 주문입니다.")

    raw = await image.read()
    arr = np.frombuffer(raw, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(422, "이미지를 읽을 수 없습니다.")

    result = extract_age_from_id(img)

    if not result["found"]:
        raise HTTPException(400, "신분증에서 생년월일을 인식하지 못했습니다. 신분증을 카메라에 정면으로 보여주세요.")
    if not result["is_adult"]:
        raise HTTPException(400, f"미성년자 (만 {result['age']}세) — 성인 전용 상품 주문 불가")

    # 중복 방지용 해시 (방법 + 나이 기반, 주민번호 저장 안 함)
    import hashlib, time
    token = hashlib.sha256(f"{order_id}:{result['raw']}:{int(time.time())//300}".encode()).hexdigest()
    dup = db.query(OrderVerification).filter(
        OrderVerification.order_id == order_id,
        OrderVerification.qr_hash == token,
    ).first()
    if dup:
        raise HTTPException(400, "방금 인증한 신분증입니다. 다른 사람의 신분증을 사용하세요.")

    db.add(OrderVerification(order_id=order.id, qr_hash=token))
    order.adult_verified_count += 1
    if order.adult_verified_count >= order.adult_verify_count:
        order.status = OrderStatus.CONFIRMED

    db.commit()
    db.refresh(order)
    return {
        "verified_count": order.adult_verified_count,
        "required_count": order.adult_verify_count,
        "completed": order.status == OrderStatus.CONFIRMED,
        "age": result["age"],
        "method": result["method"],
    }


@router.post("/{order_id}/verify-id-card")
async def verify_id_card(order_id: UUID, body: VerifyIdCard, db: Session = Depends(get_db)):
    """
    행정안전부 신분증 진위확인 API (CODEF) 연동.
    주민번호는 RSA 암호화 전송, 서버 저장 없음.
    """
    from .codef_id import verify_id_card as _verify

    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    if not order:
        raise HTTPException(404, "주문을 찾을 수 없습니다.")
    if order.status != OrderStatus.PENDING_VERIFY:
        raise HTTPException(400, "인증이 필요하지 않은 주문입니다.")

    result = await _verify(
        name=body.name,
        jumin_front=body.jumin_front,
        jumin_back=body.jumin_back,
        issue_date=body.issue_date,
    )

    if not result["authentic"]:
        raise HTTPException(400, result["error"])
    if not result["is_adult"]:
        raise HTTPException(400, result["error"])

    # 인증 성공 — QR과 동일한 카운터 처리
    qr_hash = f"idcard:{body.jumin_front[:4]}xxxx:{body.issue_date}"
    qr_hash_full = __import__("hashlib").sha256(qr_hash.encode()).hexdigest()

    dup = db.query(OrderVerification).filter(
        OrderVerification.order_id == order_id,
        OrderVerification.qr_hash == qr_hash_full,
    ).first()
    if dup:
        raise HTTPException(400, "이미 인증된 신분증입니다.")

    db.add(OrderVerification(order_id=order.id, qr_hash=qr_hash_full))
    order.adult_verified_count += 1
    if order.adult_verified_count >= order.adult_verify_count:
        order.status = OrderStatus.CONFIRMED

    db.commit()
    db.refresh(order)
    return {
        "verified_count": order.adult_verified_count,
        "required_count": order.adult_verify_count,
        "completed": order.status == OrderStatus.CONFIRMED,
        "age": result["age"],
    }


@router.get("/{order_id}/mobile-verify/{token}/kakao-start")
async def kakao_start(order_id: UUID, token: str, db: Session = Depends(get_db)):
    """카카오 로그인 시작 — 모바일 인증 페이지에서 버튼 클릭 시"""
    from .kakao_auth import make_authorize_url, is_configured

    if not is_configured():
        return HTMLResponse("<h2 style='font-family:sans-serif;padding:40px'>카카오 API 키가 설정되지 않았습니다.<br>백엔드 .env에 KAKAO_REST_API_KEY를 입력하세요.</h2>", status_code=503)

    mv = db.query(MobileVerifyToken).filter(
        MobileVerifyToken.order_id == order_id,
        MobileVerifyToken.token == token,
    ).first()
    if not mv or mv.used or datetime.utcnow() > mv.expires_at:
        return HTMLResponse("<h2 style='font-family:sans-serif;padding:40px'>유효하지 않거나 만료된 인증 링크입니다.</h2>", status_code=400)

    url = make_authorize_url(str(order_id), token)
    return RedirectResponse(url)


@router.get("/kakao-callback")
async def kakao_callback(code: str = None, state: str = None, error: str = None,
                         db: Session = Depends(get_db)):
    """카카오 OAuth 콜백 — 생년월일 스코프로 실제 나이 검증"""
    import base64
    from .kakao_auth import exchange_code, get_user_info, extract_age

    def _html(title: str, msg: str, success: bool = False) -> HTMLResponse:
        color = "#00897b" if success else "#e53935"
        icon = "✅" if success else "❌"
        return HTMLResponse(f"""<!DOCTYPE html>
<html lang="ko"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,sans-serif;background:#f5f5f5;
  min-height:100vh;display:flex;align-items:center;justify-content:center}}
.card{{background:#fff;border-radius:20px;padding:40px 28px;text-align:center;
  max-width:360px;width:90%;box-shadow:0 4px 24px rgba(0,0,0,.1)}}
.icon{{font-size:64px;margin-bottom:16px}}
h1{{font-size:20px;font-weight:800;color:{color};margin-bottom:12px}}
p{{color:#666;font-size:14px;line-height:1.6}}</style></head>
<body><div class="card">
  <div class="icon">{icon}</div>
  <h1>{title}</h1><p>{msg}</p>
</div></body></html>""")

    if error:
        return _html("인증 취소됨", "카카오 로그인이 취소되었습니다.<br>다시 시도해 주세요.")

    if not code or not state:
        return _html("오류", "잘못된 요청입니다.")

    # state 디코딩
    try:
        padded = state + "=" * (-len(state) % 4)
        decoded = base64.urlsafe_b64decode(padded).decode()
        order_id_str, token = decoded.split(":", 1)
        order_id = UUID(order_id_str)
    except Exception:
        return _html("오류", "state 파라미터가 유효하지 않습니다.")

    # 토큰 검증
    mv = db.query(MobileVerifyToken).filter(
        MobileVerifyToken.order_id == order_id,
        MobileVerifyToken.token == token,
    ).first()
    if not mv:
        return _html("오류", "유효하지 않은 인증 링크입니다.")
    if mv.used:
        return _html("이미 사용됨", "이미 사용된 인증입니다.")
    if datetime.utcnow() > mv.expires_at:
        return _html("만료됨", "인증 링크가 만료되었습니다.")

    # 카카오 코드 교환 → 생년월일로 나이 검증
    try:
        token_data = await exchange_code(code)
        access_token = token_data["access_token"]
        user_info = await get_user_info(access_token)
    except Exception as e:
        return _html("카카오 오류", f"카카오 서버 연결에 실패했습니다.<br>{str(e)[:80]}")

    age, err = extract_age(user_info)
    if err:
        return _html("나이 확인 불가", err.replace("\n", "<br>"))
    if age < 19:
        return _html("미성년자", f"만 {age}세로 확인되었습니다.<br>성인 전용 상품은 만 19세 이상만 구매 가능합니다.")

    # 인증 완료
    mv.used = True
    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    if not order:
        return _html("오류", "주문을 찾을 수 없습니다.")

    order.adult_verified_count += 1
    if order.adult_verified_count >= order.adult_verify_count:
        order.status = OrderStatus.CONFIRMED
    db.commit()

    remaining = order.adult_verify_count - order.adult_verified_count
    if remaining > 0:
        return _html(
            f"인증 완료! (만 {age}세)",
            f"성인 확인이 완료되었습니다.<br>테이블로 돌아가세요.<br><br>남은 인원: {remaining}명",
            success=True,
        )
    return _html(
        f"인증 완료! (만 {age}세)",
        "모든 인증이 완료되었습니다.<br>주문이 접수됩니다. 테이블로 돌아가세요.",
        success=True,
    )


@router.post("/kakao-verify-birthdate")
async def kakao_verify_birthdate(
    order_id: str = Form(...),
    token: str = Form(...),
    birth_year: int = Form(...),
    birth_month: int = Form(...),
    birth_day: int = Form(...),
    db: Session = Depends(get_db),
):
    """생년월일 폼 제출 → 나이 확인 → 인증 완료"""
    from datetime import date as _date

    def _html(title: str, msg: str, success: bool = False) -> HTMLResponse:
        color = "#00897b" if success else "#e53935"
        icon = "✅" if success else "❌"
        return HTMLResponse(f"""<!DOCTYPE html>
<html lang="ko"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,sans-serif;background:#f5f5f5;
  min-height:100vh;display:flex;align-items:center;justify-content:center}}
.card{{background:#fff;border-radius:20px;padding:40px 28px;text-align:center;
  max-width:360px;width:90%;box-shadow:0 4px 24px rgba(0,0,0,.1)}}
.icon{{font-size:64px;margin-bottom:16px}}
h1{{font-size:20px;font-weight:800;color:{color};margin-bottom:12px}}
p{{color:#666;font-size:14px;line-height:1.6}}</style></head>
<body><div class="card">
  <div class="icon">{icon}</div>
  <h1>{title}</h1><p>{msg}</p>
</div></body></html>""")

    if not all([order_id, token, birth_year, birth_month, birth_day]):
        return _html("오류", "모든 항목을 입력해 주세요.")

    try:
        oid = UUID(order_id)
    except Exception:
        return _html("오류", "잘못된 요청입니다.")

    mv = db.query(MobileVerifyToken).filter(
        MobileVerifyToken.order_id == oid,
        MobileVerifyToken.token == token,
    ).first()
    if not mv:
        return _html("오류", "유효하지 않은 인증 링크입니다.")
    if mv.used:
        return _html("이미 사용됨", "이미 사용된 인증입니다.")
    if datetime.utcnow() > mv.expires_at:
        return _html("만료됨", "인증 링크가 만료되었습니다.")

    # 나이 계산
    try:
        today = _date.today()
        age = today.year - birth_year - ((today.month, today.day) < (birth_month, birth_day))
    except Exception:
        return _html("오류", "생년월일이 올바르지 않습니다.")

    if age < 19:
        return _html("미성년자", f"만 {age}세로 확인되었습니다.<br>성인 전용 상품은 만 19세 이상만 구매 가능합니다.")

    mv.used = True
    order = db.query(TableOrder).filter(TableOrder.id == oid).first()
    if not order:
        return _html("오류", "주문을 찾을 수 없습니다.")

    order.adult_verified_count += 1
    if order.adult_verified_count >= order.adult_verify_count:
        order.status = OrderStatus.CONFIRMED
    db.commit()

    remaining = order.adult_verify_count - order.adult_verified_count
    if remaining > 0:
        return _html(
            f"인증 완료! (만 {age}세)",
            f"성인 확인이 완료되었습니다.<br>테이블로 돌아가세요.<br><br>남은 인원: {remaining}명",
            success=True,
        )
    return _html(
        f"인증 완료! (만 {age}세)",
        "모든 인증이 완료되었습니다.<br>주문이 접수됩니다. 테이블로 돌아가세요.",
        success=True,
    )


@router.get("/{order_id}/verify-status")
def get_verify_status(order_id: UUID, db: Session = Depends(get_db)):
    """Flutter 폴링용 — 인증 진행 상태"""
    order = db.query(TableOrder).filter(TableOrder.id == order_id).first()
    if not order:
        raise HTTPException(404, "주문을 찾을 수 없습니다.")
    return {
        "verified_count": order.adult_verified_count,
        "required_count": order.adult_verify_count,
        "completed": order.status == OrderStatus.CONFIRMED,
    }


def _order_dict(o: TableOrder) -> dict:
    return {
        "id": str(o.id),
        "table_number": o.table_number,
        "status": o.status.value,
        "total_amount": o.total_amount,
        "requires_adult_verify": o.requires_adult_verify,
        "adult_verify_count": o.adult_verify_count,
        "adult_verified_count": o.adult_verified_count,
        "created_at": o.created_at.isoformat(),
        "items": [
            {"name": i.name, "price": i.price, "quantity": i.quantity, "is_adult_only": i.is_adult_only}
            for i in o.items
        ],
    }
