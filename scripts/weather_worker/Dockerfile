FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 OPENBLAS_NUM_THREADS=1
WORKDIR /app
COPY scripts/weather_worker/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY scripts/nairobi_pipeline /app/scripts/nairobi_pipeline
COPY scripts/openmeteo_pipeline /app/scripts/openmeteo_pipeline
COPY scripts/weather_worker /app/scripts/weather_worker
COPY models/openmeteo_rainfall_v1 /app/models/openmeteo_rainfall_v1
RUN useradd --create-home worker
USER worker
ENTRYPOINT ["python", "-m", "scripts.weather_worker", "run"]
