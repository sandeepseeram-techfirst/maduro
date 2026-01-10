# Dockerfile for the Agent Runtime + Tools (Combined)
# This replaces the old python/Dockerfile and python/Dockerfile.app
FROM python:3.11-slim-bookworm

WORKDIR /app

# 1. Install System Dependencies & Tools
# We use hardcoded versions to ensure stability and avoid subshell issues
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl (v1.29.0)
RUN curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install helm (v3.14.0)
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    HELM_INSTALL_DIR=/usr/local/bin ./get_helm.sh --version v3.14.0 && \
    rm get_helm.sh

# 2. Python Environment
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PATH="/app/.venv/bin:$PATH"

# Install uv for faster pip
RUN pip install uv

# 3. Copy Source Code
# We copy the entire python directory
COPY python/ /app/python_src/

# Install Python dependencies for the custom MCP server
# Note: 'mcp[cli]' installs the SDK and CLI, but 'uvicorn' and 'fastapi' are REQUIRED 
# for running the server in SSE/HTTP mode (which FastMCP uses under the hood).
RUN pip install "mcp[cli]" uvicorn fastapi

# 4. Install Kagent ADK
WORKDIR /app/python_src
# We need to build/install the packages.
# Assuming kagent-adk is in packages/kagent-adk
WORKDIR /app/python_src/packages/kagent-adk
RUN uv pip install --system -e .
# Also install core if it exists
WORKDIR /app/python_src/packages/kagent-core
RUN if [ -f pyproject.toml ]; then uv pip install --system -e .; fi

# 5. Setup Entrypoint
WORKDIR /app
EXPOSE 8080 8084

# Copy the MCP server script to a known location
RUN cp /app/python_src/k8s_mcp_server.py /app/k8s_mcp_server.py

# By default, run the agent runtime
ENTRYPOINT ["kagent-adk"]
CMD ["static", "--host", "0.0.0.0", "--port", "8080"]
