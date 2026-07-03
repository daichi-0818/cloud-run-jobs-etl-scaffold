#!/usr/bin/env python3
"""
Single-image, multi-mode Cloud Run Job entrypoint.

The idea: instead of building/maintaining N separate Docker images for N
related ETL jobs, build ONE image and deploy it to N Cloud Run Jobs, each
with a different COLLECTOR_MODE environment variable. Each Job is paired
1:1 with a Cloud Scheduler trigger (see README for the cron pattern).

Add new modes by:
  1. Writing a new run_*() function below (keep it a thin stub here; put
     real logic in its own module once it grows).
  2. Registering it in MODE_DISPATCH.
  3. Creating a new Cloud Run Job + Scheduler entry that sets
     COLLECTOR_MODE to the new key (see scripts/deploy_jobs.sh).
"""

import logging
import os
import sys
from typing import Callable, Dict

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("collector")


def run_seo() -> None:
    """Stub: SEO / ranking-style collection job.

    TODO: your ETL logic here.
    Typical shape: fetch source -> transform -> load into warehouse.
    """
    logger.info("run_seo: starting")
    # TODO: your ETL logic here
    logger.info("run_seo: done")


def run_analysis() -> None:
    """Stub: analysis / aggregation job.

    TODO: your ETL logic here.
    """
    logger.info("run_analysis: starting")
    # TODO: your ETL logic here
    logger.info("run_analysis: done")


def run_data() -> None:
    """Stub: generic data sync job.

    TODO: your ETL logic here.
    """
    logger.info("run_data: starting")
    # TODO: your ETL logic here
    logger.info("run_data: done")


# Mode name -> handler. Mode names are lowercase, snake_case, and match the
# COLLECTOR_MODE value set on each Cloud Run Job's environment variables.
MODE_DISPATCH: Dict[str, Callable[[], None]] = {
    "seo": run_seo,
    "analysis": run_analysis,
    "data": run_data,
}


def main() -> int:
    mode = os.environ.get("COLLECTOR_MODE", "").strip().lower()

    if not mode:
        logger.error(
            "COLLECTOR_MODE is not set. Valid modes: %s",
            ", ".join(sorted(MODE_DISPATCH)),
        )
        return 2

    handler = MODE_DISPATCH.get(mode)
    if handler is None:
        logger.error(
            "Unknown COLLECTOR_MODE=%r. Valid modes: %s",
            mode,
            ", ".join(sorted(MODE_DISPATCH)),
        )
        return 2

    logger.info("Dispatching COLLECTOR_MODE=%s", mode)
    try:
        handler()
    except Exception:
        # Cloud Run Jobs treats a non-zero exit as a failed execution, which
        # is what you want for Scheduler retry / alerting to kick in.
        logger.exception("Job failed while running mode=%s", mode)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
