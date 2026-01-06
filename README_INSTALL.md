# Installing Maduro on Kubernetes

This guide will help you install Maduro on your Kubernetes cluster.

## Prerequisites

1.  **Docker**: Required to build the images.
2.  **Helm**: Required to install the charts.
3.  **Kubectl**: Required to interact with your cluster.
4.  **A Kubernetes Cluster**:
    *   **Kind (Kubernetes in Docker)**: Recommended for local testing.
    *   **Remote Cluster**: If using a remote cluster, ensure you have a container registry accessible by the cluster.

## Installation Steps (Windows)

We have provided a PowerShell script `install_maduro.ps1` to automate the build and installation process.

### 1. Setup Local Registry (If using Kind)

If you are using Kind, it is recommended to run a local registry.

```powershell
# Create a local registry container if it doesn't exist
docker run -d -p 5001:5000 --restart=always --name registry registry:2
```

### 2. Run the Installation Script

Run the script from the root of the project:

```powershell
.\install_maduro.ps1 -Version "v0.0.1" -Registry "localhost:5001" -KubeContext "kind-maduro"
```

**Parameters:**
*   `-Version`: Version tag for the images (default: `v0.0.1`).
*   `-Registry`: Docker registry to push images to (default: `localhost:5001`).
*   `-KubeContext`: Your Kubernetes context (default: `kind-maduro`). Check `kubectl config get-contexts` to find yours.

### 3. Verify Installation

Check the status of the pods:

```bash
kubectl get pods -n maduro
```

Get the UI Service URL:

```bash
kubectl get svc -n maduro
```

If you are using `LoadBalancer` type (default), you should see an `EXTERNAL-IP`. If using Kind/Minikube without a LoadBalancer provisioner, you might need to use `port-forward`:

```bash
kubectl port-forward -n maduro service/maduro-ui 8082:8080
```

Then open [http://localhost:8082](http://localhost:8082).

## Configuration Options

### Running without OpenAI (Using Ollama)

If you don't have an OpenAI API Key, you can use **Ollama** to run models locally.

1.  **Ensure Ollama is running** and accessible from your cluster.
    *   If using Kind/Docker Desktop, `host.docker.internal:11434` usually works.
    *   If using a remote cluster, you might need to deploy Ollama into the cluster or expose it via a public URL.

2.  **Install with Ollama as default**:

    ```powershell
    # In install_maduro.ps1, add this to the helm upgrade command:
    --set providers.default=ollama
    ```

    Or manually via Helm:

    ```bash
    helm upgrade --install maduro helm/maduro --namespace maduro --set providers.default=ollama
    ```

### Using Other Providers

You can also use Anthropic, Azure OpenAI, or Gemini.

```bash
# Example for Anthropic
helm upgrade --install maduro helm/maduro --namespace maduro \
  --set providers.default=anthropic \
  --set providers.anthropic.apiKey="sk-ant-..."
```

### Using OpenAI (Default)

If you have an OpenAI API Key, you can pass it to the installation script.

```powershell
# Using the install_maduro.ps1 script
.\install_maduro.ps1 -OpenAIKey "sk-your-api-key-here"
```

Or manually via Helm:

```bash
helm upgrade --install maduro helm/maduro --namespace maduro \
  --set providers.openAI.apiKey="sk-your-api-key-here"
```
