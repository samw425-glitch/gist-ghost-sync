# syntax=docker/dockerfile:1
FROM python:3.11-slim
WORKDIR /app
COPY content_api/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY content_api/ ./content_api/
EXPOSE 8088
ENV DB_PATH=/data/content-dev.sqlite
CMD ["uvicorn", "content_api.main:app", "--host", "0.0.0.0", "--port", "8088"]
