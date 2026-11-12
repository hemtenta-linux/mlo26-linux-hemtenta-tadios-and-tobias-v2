FROM python:3.12-slim

# Disable Python bytecode cache files and print logs immediately.
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt


RUN useradd --system --uid 10001 --create-home appuser

COPY app.py db.py db_setup.py schemas.py ./

USER appuser

EXPOSE 8000


CMD ["sh", "-c", "python db_setup.py && exec uvicorn app:app --host 0.0.0.0 --port 8000"]