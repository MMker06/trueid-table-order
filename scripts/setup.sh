#!/bin/bash
set -e

echo "======================================"
echo "  TrueID 배포 전 환경 설정 스크립트"
echo "======================================"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"

# 1. .env 확인
cd "$BACKEND_DIR"
if [ ! -f ".env" ]; then
  cp .env.example .env
  echo "[1/5] .env 파일 생성 — 시크릿 키 자동 생성 중..."
  python3 "$ROOT_DIR/scripts/gen_secret.py"
else
  echo "[1/5] .env 파일 확인 완료"
fi

# 2. uploads 디렉토리
mkdir -p "$BACKEND_DIR/uploads"
echo "[2/5] uploads 디렉토리 준비 완료"

# 3. Docker 확인
if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker가 설치되어 있지 않습니다."
  echo "       https://docs.docker.com/get-docker/ 에서 설치 후 다시 실행하세요."
  exit 1
fi

# 4. DB + Redis 실행
cd "$ROOT_DIR"
echo "[3/5] DB / Redis 컨테이너 실행 중..."
docker-compose up -d db redis
echo "      기동 대기 중 (15초)..."
sleep 15

# 5. API 이미지 빌드 + 마이그레이션
echo "[4/5] API 이미지 빌드 중... (첫 실행 시 수 분 소요)"
docker-compose build api
echo "      DB 마이그레이션 실행..."
docker-compose run --rm api alembic upgrade head
echo "      마이그레이션 완료"

# 6. API 서버 실행
echo "[5/5] API 서버 시작..."
docker-compose up -d api

echo ""
echo "======================================"
echo "  서버 실행 완료!"
echo "  API 문서: http://localhost:8000/docs"
echo "  헬스체크: http://localhost:8000/health"
echo "======================================"

