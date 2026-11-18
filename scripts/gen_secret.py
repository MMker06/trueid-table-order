"""
프로덕션 배포 전 .env의 시크릿 키를 안전한 랜덤 값으로 교체.
사용법: python scripts/gen_secret.py
"""
import secrets
import re
from pathlib import Path

env_path = Path(__file__).parent.parent / "backend" / ".env"
content = env_path.read_text()

new_secret = secrets.token_hex(32)
new_enc_key = secrets.token_hex(16)  # 32 hex chars = 16 bytes
new_qr_secret = secrets.token_hex(32)

content = re.sub(r"SECRET_KEY=.*", f"SECRET_KEY={new_secret}", content)
content = re.sub(r"BIOMETRIC_ENCRYPTION_KEY=.*", f"BIOMETRIC_ENCRYPTION_KEY={new_enc_key}{'x'*(32-len(new_enc_key))}", content)
if "CERT_QR_SECRET=" in content:
    content = re.sub(r"CERT_QR_SECRET=.*", f"CERT_QR_SECRET={new_qr_secret}", content)
else:
    content += f"\nCERT_QR_SECRET={new_qr_secret}\n"

env_path.write_text(content)
print(f"SECRET_KEY 갱신: {new_secret[:16]}...")
print(f"BIOMETRIC_ENCRYPTION_KEY 갱신: {new_enc_key[:8]}...")
print(f"CERT_QR_SECRET 갱신: {new_qr_secret[:16]}...")
print("완료 — .env 파일을 버전 관리에 커밋하지 마세요!")
