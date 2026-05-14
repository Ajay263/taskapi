"""
Unit tests for TaskAPI.

Why write tests before touching Docker or Kubernetes?
  - They PROVE the Python code is correct in isolation
  - When a later phase breaks something, tests pinpoint WHICH function broke
  - The CI pipeline runs these and blocks deployment if they fail
  - They document the expected behaviour in executable form

Running these tests: from the taskapi/ directory, run:
  python -m pytest app/tests/ -v
"""

import pytest
from app.tests.conftest import client   # noqa: F401  (imported for pytest fixture discovery)


async def test_health_returns_200(client):
    """Health endpoint must return 200 — Kubernetes kills pods that return anything else."""
    response = await client.get("/health")
    assert response.status_code == 200


async def test_health_response_has_required_fields(client):
    """Verify all fields Kubernetes and monitoring depend on are present."""
    response = await client.get("/health")
    data = response.json()
    assert data["status"] == "healthy"
    assert "service" in data
    assert "version" in data
    assert "environment" in data
    assert "checks" in data


async def test_list_tasks_empty_initially(client):
    """Fresh app returns empty list — confirms in-memory store starts clean."""
    response = await client.get("/tasks")
    assert response.status_code == 200
    assert response.json() == []


async def test_create_task_returns_201(client):
    """HTTP 201 Created is the correct status code for resource creation (not 200)."""
    response = await client.post("/tasks", json={
        "title": "Learn Kubernetes",
        "description": "Complete this guide",
        "done": False,
    })
    assert response.status_code == 201


async def test_created_task_has_auto_id(client):
    """The server assigns an integer ID — the client never sends an ID."""
    response = await client.post("/tasks", json={"title": "Auto ID test"})
    data = response.json()
    assert "id" in data
    assert isinstance(data["id"], int)
    assert data["id"] >= 1


async def test_created_task_fields_match_request(client):
    """Response body must reflect exactly what was sent."""
    response = await client.post("/tasks", json={
        "title": "Exact fields",
        "description": "Check all fields",
        "done": False,
    })
    data = response.json()
    assert data["title"] == "Exact fields"
    assert data["description"] == "Check all fields"
    assert data["done"] is False
    assert "created_at" in data


async def test_get_task_by_id(client):
    """Fetching by ID returns that specific task."""
    create = await client.post("/tasks", json={"title": "Find me by ID"})
    task_id = create.json()["id"]
    response = await client.get(f"/tasks/{task_id}")
    assert response.status_code == 200
    assert response.json()["title"] == "Find me by ID"


async def test_get_missing_task_returns_404(client):
    """Requesting a non-existent task must return 404 — not 500."""
    response = await client.get("/tasks/999999")
    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


async def test_missing_title_returns_422(client):
    """FastAPI validates the request body — missing required field → 422."""
    response = await client.post("/tasks", json={"description": "No title field"})
    assert response.status_code == 422


async def test_delete_task(client):
    """Delete returns 204 No Content and the task is gone afterward."""
    create = await client.post("/tasks", json={"title": "Delete me"})
    task_id = create.json()["id"]
    delete = await client.delete(f"/tasks/{task_id}")
    assert delete.status_code == 204
    get = await client.get(f"/tasks/{task_id}")
    assert get.status_code == 404


async def test_metrics_endpoint_returns_prometheus_format(client):
    """The /metrics endpoint must return Prometheus text format."""
    response = await client.get("/metrics")
    assert response.status_code == 200
    # Prometheus text format: metric lines start with the metric name
    assert b"taskapi_requests_total" in response.content