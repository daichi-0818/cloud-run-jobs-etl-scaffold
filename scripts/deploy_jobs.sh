#!/usr/bin/env bash
# Build one image, deploy it to N Cloud Run Jobs, each pinned to a mode via
# COLLECTOR_MODE. Re-run this script any time you ship a new image — it
# re-applies the image AND re-applies every env var on every job, which
# sidesteps the "update wipes env vars" gotcha (see README).
set -euo pipefail

# --- Config: replace these placeholders for your project -------------------
PROJECT_ID="<YOUR_PROJECT>"
REGION="<YOUR_REGION>"                 # e.g. us-central1
AR_REPO="<YOUR_AR_REPO>"               # Artifact Registry repo name
IMAGE_NAME="<YOUR_IMAGE_NAME>"         # e.g. etl-collector
SERVICE_ACCOUNT="<YOUR_JOB_SA>@${PROJECT_ID}.iam.gserviceaccount.com"

# job-name:mode pairs. One Cloud Run Job per mode, one Scheduler entry per Job.
JOBS=(
  "example-job-seo:seo"
  "example-job-analysis:analysis"
  "example-job-data:data"
)

IMAGE_TAG="${1:-latest}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "== Building and pushing ${IMAGE_URI} =="
gcloud builds submit --tag "${IMAGE_URI}" --project "${PROJECT_ID}" .

for entry in "${JOBS[@]}"; do
  job_name="${entry%%:*}"
  mode="${entry##*:}"

  echo "== Deploying ${job_name} (COLLECTOR_MODE=${mode}) =="

  if gcloud run jobs describe "${job_name}" \
      --project "${PROJECT_ID}" --region "${REGION}" >/dev/null 2>&1; then
    # Job exists: update it. IMPORTANT — see README gotcha on env vars.
    # We always pass --set-env-vars explicitly on every update so the mode
    # is never silently dropped when the image changes.
    gcloud run jobs update "${job_name}" \
      --project "${PROJECT_ID}" \
      --region "${REGION}" \
      --image "${IMAGE_URI}" \
      --service-account "${SERVICE_ACCOUNT}" \
      --set-env-vars "COLLECTOR_MODE=${mode}" \
      --task-timeout=900 \
      --max-retries=1
  else
    # Job does not exist yet: create it.
    gcloud run jobs create "${job_name}" \
      --project "${PROJECT_ID}" \
      --region "${REGION}" \
      --image "${IMAGE_URI}" \
      --service-account "${SERVICE_ACCOUNT}" \
      --set-env-vars "COLLECTOR_MODE=${mode}" \
      --task-timeout=900 \
      --max-retries=1
  fi
done

echo "== Done. Remember: Cloud Scheduler triggers are separate resources. =="
echo "== See README.md 'Cloud Scheduler wiring' for the gcloud scheduler command. =="
