import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_health():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

@pytest.mark.asyncio
async def test_create_task():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post("/tasks", json={
            "title": "Test task",
            "description": "This is a test"
        })
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Test task"
    assert "id" in data

@pytest.mark.asyncio
async def test_list_tasks():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/tasks")
    assert response.status_code == 200
    assert "tasks" in response.json()

@pytest.mark.asyncio
async def test_task_not_found():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/tasks/999999")
    assert response.status_code == 404