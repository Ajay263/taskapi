# ════════════════════════════════════════════════════════════════════════════
# STAGE 1: builder
# Purpose: install Python packages into a virtual environment.
# This stage is DISCARDED — it never reaches production.
# All build tools (gcc, pip cache, etc.) stay here.
# ════════════════════════════════════════════════════════════════════════════
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build-time dependencies
# --no-install-recommends: only install what's strictly required (smaller image)
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential gcc \
    && rm -rf /var/lib/apt/lists/*

# Create a virtual environment.
# We use a venv so Stage 2 can copy it cleanly as a single directory.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy requirements first — Docker layer caching.
# If requirements.txt is unchanged, Docker reuses the cached layer with
# all installed packages. Only changes to requirements.txt trigger pip install.
# This makes rebuilds fast when only app code changes.
COPY app/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# ════════════════════════════════════════════════════════════════════════════
# STAGE 2: production
# Purpose: minimal runtime image with app code and packages only.
# Contains: Python 3.11-slim + venv from builder + app code.
# Does NOT contain: build-essential, gcc, pip, compile cache.
# ════════════════════════════════════════════════════════════════════════════
FROM python:3.11-slim AS production

# ── Security: non-root user ────────────────────────────────────────────────
# If the container is ever compromised (e.g., remote code execution),
# running as root gives the attacker root on the container file system.
# Running as UID 1001 limits blast radius. CIS Kubernetes Benchmark requires this.
RUN groupadd --gid 1001 appgroup \
    && useradd \
        --uid 1001 \
        --gid appgroup \
        --no-create-home \
        --shell /sbin/nologin \
        appuser

WORKDIR /app

# Copy the virtual environment from the builder stage (packages only, no build tools)
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application source code
COPY app/ .

# Set ownership so our non-root user can read the files
RUN chown -R appuser:appgroup /app

# Switch to non-root user for all subsequent instructions and at runtime
USER appuser

# Document which port the app uses (informational only — does not publish)
EXPOSE 8000

# ── Build-time metadata (OCI image labels) ─────────────────────────────────
# These let you inspect any running container and trace it back to:
#   - Which Git commit built it
#   - When it was built
#   - Which version it is
# Useful for: audit trails, debugging, compliance
ARG APP_VERSION=dev
ARG BUILD_DATE
ARG GIT_COMMIT
LABEL org.opencontainers.image.title="taskapi"
LABEL org.opencontainers.image.version="${APP_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.source="https://github.com/YOUR_USERNAME/taskapi"

# ── Docker health check ─────────────────────────────────────────────────────
# Separate from Kubernetes probes (Phase 6 adds those).
# `docker ps` shows (healthy) or (unhealthy) based on this.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# ── Start command ───────────────────────────────────────────────────────────
# We run uvicorn main:app (not app.main:app) because WORKDIR is /app and
# COPY app/ . puts main.py directly in /app — so Python sees it as 'main', not 'app.main'.
# --workers 1: Kubernetes handles scaling via replicas (multiple pods).
#              Multiple workers per pod causes unpredictable resource usage.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--log-level", "warning"]