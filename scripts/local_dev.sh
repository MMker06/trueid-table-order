#!/bin/bash
# Docker 없이 로컬 개발 환경 실행 (venv 사용)
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_DIR="$BACKEND_DIR/.venv"

echo "=== TrueID 로컬 개발 환경 ==="

# 1. Python 버전 확인
if ! python3 -c "import sys; assert sys.version_info >= (3,11)" 2>/dev/null; then
  echo "ERROR: Python 3.11 이상이 필요합니다."
  exit 1
fi

# 2. venv 생성
if [ ! -d "$VENV_DIR" ]; then
  echo "[1/4] 가상환경 생성..."
  python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
echo "[1/4] 가상환경 활성화 완료: $VENV_DIR"

# 3. 의존성 설치 (dlib 없는 requirements 사용)
echo "[2/4] 패키지 설치 중..."
pip install --upgrade pip -q
pip install -r "$BACKEND_DIR/requirements.txt" -q
echo "      설치 완료"

# 4. .env 확인
cd "$BACKEND_DIR"
if [ ! -f ".env" ]; then
  cp .env.example .env
  python3 "$ROOT_DIR/scripts/gen_secret.py"
fi

# 5. PostgreSQL/Redis가 로컬에 실행 중인지 확인 후 서버 시작
echo "[3/4] 서버 시작..."
echo "      ※ PostgreSQL(5432)과 Redis(6379)가 로컬에서 실행 중이어야 합니다."
echo ""

uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
