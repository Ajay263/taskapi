import os
import logging
import json
import time
from datetime import datetime
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

# ─── Structured Logging (JSON format for Loki) ─────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "service": "taskapi",
            "version": os.getenv("APP_VERSION", "unknown"),
            "environment": os.getenv("ENVIRONMENT", "unknown"),
            "message": record.getMessage(),
        }
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry)

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger = logging.getLogger("taskapi")
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# ─── Prometheus Metrics ────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "taskapi_requests_total",
    "Total request count",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "taskapi_request_duration_seconds",
    "Request latency in seconds",
    ["method", "endpoint"]
)
TASKS_CREATED = Counter("taskapi_tasks_created_total", "Total tasks created")

# ─── App ───────────────────────────────────────────────────────────────────
app = FastAPI(title="TaskAPI", version="1.0.0")

# In-memory storage (in prod, this would be a database)
tasks_store = {}
task_counter = 0

# Simulated DB password from Vault (injected via environment variable)
DB_PASSWORD = os.getenv("DB_PASSWORD", "NOT_SET")

class Task(BaseModel):
    title: str
    description: str = ""
    done: bool = False

class TaskResponse(Task):
    id: int
    created_at: str

@app.middleware("http")
async def metrics_middleware(request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time
    
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)
    
    logger.info(f"{request.method} {request.url.path} → {response.status_code} ({duration:.3f}s)")
    return response

@app.get("/health")
def health():
    """
    Kubernetes liveness and readiness probe endpoint.
    In production, also check DB connectivity here.
    """
    # Check if secret was injected (would check DB connection in real scenario)
    if DB_PASSWORD == "NOT_SET":
        logger.warning("DB_PASSWORD not set — Vault integration may be missing")
    
    return {
        "status": "healthy",
        "service": "taskapi",
        "version": os.getenv("APP_VERSION", "unknown"),
        "environment": os.getenv("ENVIRONMENT", "unknown"),
        "vault_secret_present": DB_PASSWORD != "NOT_SET"
    }

@app.get("/tasks")
def list_tasks():
    logger.info(f"Listing {len(tasks_store)} tasks")
    return {"tasks": list(tasks_store.values()), "total": len(tasks_store)}

@app.post("/tasks", status_code=201)
def create_task(task: Task):
    global task_counter
    task_counter += 1
    task_id = task_counter
    
    task_data = {
        "id": task_id,
        "title": task.title,
        "description": task.description,
        "done": task.done,
        "created_at": datetime.utcnow().isoformat()
    }
    tasks_store[task_id] = task_data
    TASKS_CREATED.inc()
    logger.info(f"Created task #{task_id}: {task.title}")
    return task_data

@app.get("/tasks/{task_id}")
def get_task(task_id: int):
    if task_id not in tasks_store:
        logger.warning(f"Task #{task_id} not found")
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    return tasks_store[task_id]

@app.get("/metrics")
def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)