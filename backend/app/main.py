from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
import logging
import os

from .core.database import engine, Base
from .api.v1.router import api_router

# 모델 import — Base.metadata 등록용
from .models import User, Merchant, MenuCategory, MenuItem, TableOrder, OrderItem, OrderVerification, MobileVerifyToken

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("패스체크 서버 시작 — DB 테이블 초기화")
    Base.metadata.create_all(bind=engine)
    # YOLO 워밍업 — 백그라운드 스레드로 (시작 블로킹 방지)
    import threading
    def _warmup():
        try:
            from .api.v1.endpoints.ai_detect import warmup
            warmup()
            logger.info("YOLOv8n 워밍업 완료")
        except Exception as e:
            logger.warning(f"YOLO 워밍업 실패: {e}")
    threading.Thread(target=_warmup, daemon=True).start()
    yield
    logger.info("패스체크 서버 종료")


app = FastAPI(
    title="패스체크 API",
    description="AI 기반 성인 인증 + 테이블 오더 시스템",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/docs",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)

# 이미지 정적 파일 서빙
_static_dir = "/app/static"
if os.path.isdir(_static_dir):
    app.mount("/static", StaticFiles(directory=_static_dir), name="static")


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "패스체크"}
