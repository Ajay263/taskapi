"""
TaskAPI — Task Management REST API

This application is intentionally simple. The DevOps infrastructure
around it is the point of the training, not the app itself.

What each part of this app exercises:
  /health endpoint    → Kubernetes liveness and readiness probes (Phase 6)
  /metrics endpoint   → Scraped by Prometheus every 15 seconds (Phase 13)
  Structured logging  → Parsed and indexed by Loki (Phase 14)
  OpenTelemetry       → Traces sent to Jaeger (Phase 15)
  DB_PASSWORD env var → Injected from Vault at runtime (Phase 7)
"""

import os
import logging
import json
import time
from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# ── Structured JSON Logging ───────────────────────────────────────────────────
#
# Why JSON logging?
# Log aggregators like Loki parse log lines and let you filter by field value.
# Plain text like "INFO 2024-01-01 task created" requires fragile regex to parse.
# JSON like {"level":"INFO","message":"task created","task_id":1} is structured —
# you can query: {app="taskapi"} | json | level="ERROR" directly in Grafana.
#
class JSONFormatter(logging.Formatter):
    """Formats every log record as a single JSON line."""
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level":     record.levelname,
            "service":   "taskapi",
            "version":   os.getenv("APP_VERSION", "dev"),
            "environment": os.getenv("ENVIRONMENT", "local"),
            "message":   record.getMessage(),
        }
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry)

_handler = logging.StreamHandler()
_handler.setFormatter(JSONFormatter())
logger = logging.getLogger("taskapi")
logger.addHandler(_handler)
logger.setLevel(logging.getLevelName(os.getenv("LOG_LEVEL", "INFO")))
logging.getLogger("uvicorn.access").propagate = False   # Avoid duplicate access logs

# ── Prometheus Metrics ────────────────────────────────────────────────────────
#
# Prometheus uses a PULL model: it calls /metrics every 15-30 seconds.
# Your app accumulates metric values in memory.
# When Prometheus pulls, these objects serialise to the Prometheus text format.
#
# Counter: only goes up (total requests, total errors)
# Histogram: records a distribution (request durations, response sizes)
#
REQUEST_COUNT = Counter(
    "taskapi_requests_total",
    "Total number of HTTP requests",
    ["method", "endpoint", "http_status"],  # Labels = dimensions to slice by in Grafana
)
REQUEST_LATENCY = Histogram(
    "taskapi_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    # Bucket boundaries in seconds — defines histogram resolution
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)
TASKS_CREATED = Counter(
    "taskapi_tasks_created_total",
    "Total number of tasks created",
)

# ── Pydantic Models ───────────────────────────────────────────────────────────
# These define the shape of request bodies and response bodies.
# FastAPI validates every request against these models automatically.
# If a required field is missing → 422 Unprocessable Entity before your code runs.

class TaskCreate(BaseModel):
    title: str
    description: Optional[str] = ""
    done: bool = False

    model_config = {
        "json_schema_extra": {
            "example": {
                "title": "Deploy to production",
                "description": "Run the readiness checklist first",
                "done": False,
            }
        }
    }

class TaskResponse(BaseModel):
    id: int
    title: str
    description: str
    done: bool
    created_at: str

# ── FastAPI Application ───────────────────────────────────────────────────────
app = FastAPI(
    title="TaskAPI",
    description="Task management API · DevSecOps training project",
    version=os.getenv("APP_VERSION", "dev"),
    docs_url="/docs",    # Swagger UI — open this in your browser to test the API
    redoc_url="/redoc",  # Alternative documentation UI
)

# In-memory storage — in production this would be a database
_tasks: dict[int, dict] = {}
_next_id: int = 0

# Read the database password from environment.
# Phase 7 (Vault) will inject the real value.
# For now, warn if it is not set.
DB_PASSWORD = os.getenv("DB_PASSWORD", "NOT_CONFIGURED")
if DB_PASSWORD == "NOT_CONFIGURED":
    logger.warning("DB_PASSWORD env var not set — expected when Vault is not yet configured")

# ── Request Middleware ────────────────────────────────────────────────────────
# Middleware runs on EVERY request before and after the route handler.
# We use it to: record latency, count requests by status code, log each request.
# This is one place to add cross-cutting concerns without touching route code.
@app.middleware("http")
async def observe_requests(request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        http_status=str(response.status_code),
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path,
    ).observe(duration)

    logger.info(
        f"{request.method} {request.url.path} "
        f"→ {response.status_code} ({duration * 1000:.1f}ms)"
    )
    return response

# ── Health Endpoint ───────────────────────────────────────────────────────────
# Kubernetes calls this endpoint periodically (Phase 6 explains exactly how).
# Rules for health endpoints:
#   - Must return 200 when the app is ready to serve traffic
#   - Must return non-200 when it is not (so Kubernetes stops sending traffic)
#   - Must be fast — Kubernetes will time it out at ~5 seconds
#   - Must NEVER crash — even if the DB is down, return a degraded status
@app.get("/health", tags=["Operations"])
def health_check():
    vault_ok = DB_PASSWORD != "NOT_CONFIGURED"
    return {
        "status": "healthy",
        "service": "taskapi",
        "version": os.getenv("APP_VERSION", "dev"),
        "environment": os.getenv("ENVIRONMENT", "local"),
        "checks": {
            "vault_secret": "ok" if vault_ok else "missing — expected until Phase 7",
        },
    }

# ── Task Endpoints ────────────────────────────────────────────────────────────
@app.get("/tasks", response_model=list[TaskResponse], tags=["Tasks"])
def list_tasks():
    logger.info(f"Listing {len(_tasks)} tasks")
    return list(_tasks.values())

@app.post("/tasks", response_model=TaskResponse, status_code=201, tags=["Tasks"])
def create_task(task: TaskCreate):
    """Returns HTTP 201 Created. FastAPI validates the request body automatically."""
    global _next_id
    _next_id += 1
    task_data = {
        "id": _next_id,
        "title": task.title,
        "description": task.description or "",
        "done": task.done,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    _tasks[_next_id] = task_data
    TASKS_CREATED.inc()
    logger.info(f"Created task #{_next_id}: '{task.title}'")
    return task_data

@app.get("/tasks/{task_id}", response_model=TaskResponse, tags=["Tasks"])
def get_task(task_id: int):
    if task_id not in _tasks:
        logger.warning(f"Task #{task_id} not found")
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    return _tasks[task_id]

@app.patch("/tasks/{task_id}", response_model=TaskResponse, tags=["Tasks"])
def update_task(task_id: int, task: TaskCreate):
    if task_id not in _tasks:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    _tasks[task_id].update({
        "title": task.title,
        "description": task.description or "",
        "done": task.done,
    })
    logger.info(f"Updated task #{task_id}")
    return _tasks[task_id]

@app.delete("/tasks/{task_id}", status_code=204, tags=["Tasks"])
def delete_task(task_id: int):
    if task_id not in _tasks:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    del _tasks[task_id]
    logger.info(f"Deleted task #{task_id}")
    return None

# ── Metrics Endpoint ──────────────────────────────────────────────────────────
# Prometheus scrapes this endpoint. We exclude it from the Swagger docs
# because it is not part of the public API.
@app.get("/metrics", tags=["Operations"], include_in_schema=False)
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)