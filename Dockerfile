FROM python:3.12-slim

WORKDIR /app

# If you add dependencies, put them in requirements.txt and uncomment:
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

# COLLECTOR_MODE is intentionally NOT set here — it is provided per-Job via
# `gcloud run jobs deploy/update --set-env-vars COLLECTOR_MODE=<mode>`.
# See README.md "Mode dispatch" and scripts/deploy_jobs.sh.
ENTRYPOINT ["python", "src/collector.py"]
