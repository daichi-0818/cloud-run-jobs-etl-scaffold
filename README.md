# cloud-run-jobs-etl-scaffold

[![CI](https://github.com/daichi-0818/cloud-run-jobs-etl-scaffold/actions/workflows/ci.yml/badge.svg)](https://github.com/daichi-0818/cloud-run-jobs-etl-scaffold/actions/workflows/ci.yml)

A minimal scaffold for running several related, scheduled ETL jobs as
**one Docker image deployed to N Cloud Run Jobs**, each job pinned to a
different mode via an environment variable. Grew out of the pattern of
manually running a handful of one-off ETL scripts and wanting a single,
consistent way to containerize and schedule all of them without maintaining
N separate images or N separate codebases.

## What problem this solves

If you have several independent-but-related batch jobs (e.g. "collect SEO
rankings", "run daily analysis", "sync raw data") you have two common ways
to ship them on Cloud Run:

1. **One image per job.** Simple mentally, but you now maintain N
   Dockerfiles, N build pipelines, and N sets of dependencies that drift
   apart over time.
2. **One image, N jobs, mode-switched by env var.** One Dockerfile, one
   build, one dependency set. Each Cloud Run Job is just "the same image +
   a different `COLLECTOR_MODE` value". This scaffold implements option 2.

Trade-off: all modes share one dependency footprint and one image size.
Fine for small-to-medium ETL scripts; if one mode needs a heavyweight
dependency the others don't, reconsider splitting it out.

## Mode dispatch

`src/collector.py` reads `COLLECTOR_MODE` from the environment and
dispatches to a `run_*()` function:

```
COLLECTOR_MODE=seo       -> run_seo()
COLLECTOR_MODE=analysis  -> run_analysis()
COLLECTOR_MODE=data      -> run_data()
```

Each `run_*()` is a stub in this scaffold (`# TODO: your ETL logic here`).
Add a new mode by writing a new `run_*()` function, registering it in
`MODE_DISPATCH`, and adding a matching entry in `scripts/deploy_jobs.sh`.

Unset or unrecognized `COLLECTOR_MODE` exits non-zero with a log message
listing valid modes — this is what makes a misconfigured Job/Scheduler pair
fail loudly instead of silently doing nothing.

## Cloud Scheduler wiring

The pattern is **1 Cloud Run Job = 1 mode = 1 Cloud Scheduler trigger.**
Scheduler doesn't call the job directly with parameters — the mode is baked
into the Job's own environment variables at deploy time (see
`scripts/deploy_jobs.sh`). Scheduler's only role is to hit the Cloud Run
Jobs "run" API on a cron schedule.

Example (replace placeholders):

```bash
gcloud scheduler jobs create http example-job-seo-trigger \
  --project=<YOUR_PROJECT> \
  --location=<YOUR_REGION> \
  --schedule="0 6 * * *" \
  --uri="https://<YOUR_REGION>-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/<YOUR_PROJECT>/jobs/example-job-seo:run" \
  --http-method=POST \
  --oauth-service-account-email=<YOUR_SCHEDULER_SA>@<YOUR_PROJECT>.iam.gserviceaccount.com
```

Give the Scheduler service account the `roles/run.invoker` role on each Job
it needs to trigger.

## Known gotchas

- **`gcloud run jobs update --image ...` can reset environment variables
  you didn't explicitly pass.** Cloud Run Jobs updates replace the env var
  set with whatever you specify on that call — it is not a merge. If you
  update the image without re-passing `--set-env-vars`, the Job can lose
  its `COLLECTOR_MODE` (and any other env vars) and start failing or,
  worse, silently running the wrong mode if you have a default fallback.
  **Mitigation:** `scripts/deploy_jobs.sh` always passes the full
  `--set-env-vars` list on every update, never relies on "it was already
  set." Treat every `gcloud run jobs update` as if it were a full
  replacement of config, not a patch.

- **No default `COLLECTOR_MODE`.** This scaffold deliberately fails hard
  (exit code 2) when the mode is missing or unrecognized, rather than
  falling back to some default job. A silent default is how you end up
  running the wrong ETL against the wrong schedule.

- **`--max-retries` interacts with partial-failure ETL.** If your `run_*()`
  logic is not idempotent (e.g. it appends rows rather than upserts),
  a Cloud Run Jobs retry after partial failure can double-write. Either
  make the job idempotent or set `--max-retries=0` and handle failure
  via alerting instead.

- **Task timeout vs. actual runtime.** `--task-timeout` defaults are easy
  to forget to raise for slow jobs; a job that gets killed mid-write can
  leave a partial write behind. Size the timeout with margin and make
  writes idempotent where possible.

- **One image, shared dependencies.** Adding a heavy dependency for one
  mode bloats the image (and cold-start / build time) for every mode.
  If modes diverge significantly in their dependency footprint, that's a
  signal to split the image, not force it into this scaffold.

- **Local testing needs the env var too.** Since dispatch is 100%
  environment-driven, forgetting to set `COLLECTOR_MODE` locally is the
  most common "why did nothing happen" moment. `COLLECTOR_MODE=seo python
  src/collector.py` is the minimum invocation.

## Quickstart

```bash
# 1. Run a mode locally
COLLECTOR_MODE=seo python3 src/collector.py

# 2. Build the image locally (optional smoke test)
docker build -t etl-collector:local .
docker run --rm -e COLLECTOR_MODE=seo etl-collector:local

# 3. Fill in placeholders in cloudbuild.yaml and scripts/deploy_jobs.sh:
#    <YOUR_PROJECT>, <YOUR_REGION>, <YOUR_AR_REPO>, <YOUR_IMAGE_NAME>,
#    <YOUR_JOB_SA>, and the JOBS array (job-name:mode pairs)

# 4. Build + deploy to all configured Cloud Run Jobs
bash scripts/deploy_jobs.sh

# 5. Wire up Cloud Scheduler triggers (see "Cloud Scheduler wiring" above),
#    one per Job.
```

## Layout

```
src/collector.py       # COLLECTOR_MODE dispatch entrypoint (run_* are stubs)
Dockerfile              # Generic Python 3.12 image
cloudbuild.yaml         # SHORT_SHA-tagged build config (placeholders)
scripts/deploy_jobs.sh  # Build -> deploy to N Cloud Run Jobs (placeholders)
```

## License

MIT — see LICENSE.
