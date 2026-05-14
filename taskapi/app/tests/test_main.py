import pytest
from fastapi.testclient import TestClient
import sys
import os

# Add parent directory to path so we can import main
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Now import from main
from main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert "TaskAPI" in response.json()["service"]

def test_create_task():
    response = client.post("/tasks", json={
        "title": "Learn Kubernetes",
        "description": "Complete the DevSecOps training"
    })
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Learn Kubernetes"
    assert data["id"] == 1

def test_list_tasks():
    response = client.get("/tasks")
    assert response.status_code == 200
    assert response.json()["total"] == 1

def test_get_task_not_found():
    response = client.get("/tasks/999")
    assert response.status_code == 404
