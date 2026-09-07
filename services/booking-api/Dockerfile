FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV DD_LOGS_INJECTION=true
ENV DD_PROFILING_ENABLED=true
# gunicorn rather than the Flask dev server: the demo generates real concurrent
# load, and the dev server serialises it into misleading latency.
CMD ["ddtrace-run", "gunicorn", "--bind", "0.0.0.0:8082", "--workers", "2", "--threads", "8", "--access-logfile", "-", "app:app"]
