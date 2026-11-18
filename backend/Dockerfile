FROM python:3.11-slim

# 시스템 의존성 (OpenCV, psycopg2 컴파일 등)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    gcc \
    g++ \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 의존성 먼저 설치 (캐시 활용)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p uploads

EXPOSE ${PORT:-8000}
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
