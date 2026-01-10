# Maduro - Cloud Native AI Agent Platform

Maduro is a Kubernetes-native AI agent platform powered by [Kagent](https://kagent.dev). It enables you to deploy, manage, and interact with autonomous AI agents directly within your Kubernetes cluster.

## Architecture Overview

The system consists of three main components:

### 1. Kagent Controller (Go)
The brain of the operation. It runs as a Kubernetes Controller and reconciles custom resources:
- **Agent**: Defines the AI agent's personality, model configuration, and capabilities.
- **RemoteMCPServer**: Defines external tool servers that agents can use.
- **ModelConfig**: Manages LLM provider credentials and settings.

The Controller translates these high-level resources into Kubernetes primitives (Deployments, Services, Secrets) and orchestrates the agent lifecycle.

### 2. Tool Server (Python / FastMCP)
Provides the actual capabilities (Tools) to the agents using the Model Context Protocol (MCP).
- **Implementation**: `python/k8s_mcp_server.py`
- **Protocol**: Streamable HTTP (POST) or SSE.
- **Tools Provided**:
    - `k8s_get_resources`: Fetch Kubernetes resources.
    - `k8s_get_available_api_resources`: List API resources.
    - `echo_test`: Debugging tool.
- **Key Features**:
    - **HostHeaderMiddleware**: Custom middleware to rewrite Host headers to `localhost`, allowing it to run behind Kubernetes Services while satisfying FastMCP's strict security checks.
    - **HTTP/1.1 Enforcement**: Forces `h11` protocol to avoid HTTP/2 connection coalescing issues (421 Misdirected Request).

### 3. Agent Runtime (Python / Kagent ADK)
The execution environment for the AI agents.
- **Image**: Built from `deploy_v2/Dockerfile.app` using the `kagent-adk` package.
- **Entrypoint**: `kagent-adk static`.
- **Function**: Connects to the LLM (OpenAI) and the Tool Server (via MCP) to execute tasks defined by the user.

### 4. User Interface (Next.js)
A modern web interface to interact with agents and manage tools.
- **Port**: 8080
- **Features**: Chat interface, Agent management, Tool discovery.

## Deployment Workflow

The project uses a custom deployment script `deploy_v2.sh` designed for rapid iteration:
1.  **Unique Registry**: Generates a timestamped `ttl.sh` registry (e.g., `ttl.sh/maduro-v2-<timestamp>`) to guarantee fresh image pulls.
2.  **Build**: Builds Docker images for Controller, Tools, App (Agent), and UI.
3.  **Push**: Pushes images to the ephemeral registry.
4.  **Deploy**: Uses Helm to upgrade the release, injecting the new image tags dynamically.

## Quick Start

### Prerequisites
- Kubernetes Cluster (Kind, Minikube, or Remote)
- `kubectl` configured
- `docker` installed
- OpenAI API Key

### Deployment
1.  **Set your OpenAI API Key**:
    ```bash
    kubectl create secret generic kagent-openai --from-literal=OPENAI_API_KEY=sk-your-key... -n maduro
    ```

2.  **Run Deployment Script**:
    ```bash
    bash deploy_v2.sh
    ```

3.  **Access UI**:
    Forward the UI port:
    ```bash
    kubectl port-forward svc/maduro-ui 8080:8080 -n maduro
    ```
    Open http://localhost:8080.

## Troubleshooting

### Common Issues
- **Agent Error (Connection Closed)**: Usually means the Tool Server rejected the connection (421 or 404). Check `maduro-tools` logs.
- **Agent Error (No such option: --host)**: Mismatch between Controller logic and Agent image. Ensure you are using the latest `deploy_v2.sh` which forces image updates.
- **OpenAI 429**: Quota exceeded. Check your billing.

### Logs
- **Agent**: `kubectl logs -n maduro deployment/k8s-a2a-agent --all-containers=true`
- **Tools**: `kubectl logs -n maduro deployment/maduro-tools`
- **Controller**: `kubectl logs -n maduro deployment/maduro-controller`

## Development Notes

- **Adding Tools**: Edit `python/k8s_mcp_server.py` and add functions decorated with `@mcp.tool()`.
- **Modifying Agent**: Edit `helm/agents/k8s-a2a/templates/agent.yaml` to change prompts or skills.
