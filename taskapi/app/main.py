"""
TaskAPI - A simple task management REST API
This is our application. Keep it simple - the infrastructure is the lesson.
"""

import os
import logging
import json
from datetime import datetime
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# --- Structured Logging (JSON format) ---
# Why JSON? Loki (our log aggregator) can parse JSON logs automatically.
# We can then search by level, service name, etc.
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "service": "taskapi",
            "version": os.getenv("APP_VERSION", "unknown"),
            "environment": os.getenv("ENVIRONMENT", "development"),
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

# --- FastAPI App ---
app = FastAPI(
    title="TaskAPI",
    description="Simple task management API",
    version="1.0.0"
)

# In-memory storage (in production this would be a database)
tasks_store = {}
task_counter = 0


class Task(BaseModel):
    """Task model for POST/PUT requests"""
    title: str
    description: str = ""
    done: bool = False


class TaskResponse(Task):
    """Task model for GET responses (includes auto-generated fields)"""
    id: int
    created_at: str


@app.get("/health")
def health():
    """
    Health check endpoint.
    Kubernetes uses this for liveness and readiness probes.
    A production health check would also verify database connectivity.
    """
    return {
        "status": "healthy",
        "service": "taskapi",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/")
def root():
    """Root endpoint with API information"""
    return {
        "service": "TaskAPI",
        "version": "1.0.0",
        "endpoints": ["/health", "/tasks", "/tasks/{id}", "/docs"]
    }


@app.get("/tasks")
def list_tasks():
    """List all tasks"""
    logger.info(f"Listing {len(tasks_store)} tasks")
    return {
        "tasks": list(tasks_store.values()),
        "total": len(tasks_store)
    }


@app.post("/tasks", status_code=201)
def create_task(task: Task):
    """Create a new task"""
    global task_counter
    task_counter += 1
    task_id = task_counter
    
    task_data = TaskResponse(
        id=task_id,
        title=task.title,
        description=task.description,
        done=task.done,
        created_at=datetime.utcnow().isoformat()
    )
    tasks_store[task_id] = task_data.dict()
    logger.info(f"Created task #{task_id}: {task.title}")
    return task_data


@app.get("/tasks/{task_id}")
def get_task(task_id: int):
    """Get a specific task by ID"""
    if task_id not in tasks_store:
        logger.warning(f"Task #{task_id} not found")
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    return tasks_store[task_id]