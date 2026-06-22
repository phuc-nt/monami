# monami voice backend — container for Cloud Run.
# Runs the FastAPI WS relay; auth = Application Default Credentials (the Cloud
# Run service account in prod). No key file is ever baked into the image.

FROM python:3.13-slim

# Don't buffer logs; no .pyc files.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install deps first for layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App code (the .dockerignore keeps out .env, profiles/, venv, caches, tests).
COPY . .

# Cloud Run provides $PORT (default 8080); bind 0.0.0.0 so it's reachable.
ENV PORT=8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
