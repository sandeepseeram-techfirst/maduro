#!/bin/bash
set -e

# Configuration
NAMESPACE=${NAMESPACE:-"maduro"}
RELEASE_NAME=${RELEASE_NAME:-"maduro"}
VERSION=${VERSION:-"0.0.1"}
REGISTRY=${REGISTRY:-"localhost:5001"}
REPO=${REPO:-"maduro-dev/maduro"}

echo "=== Starting Clean Build & Install ==="

# 1. Ensure Helm Charts exist and are valid
echo "--> Recreating Helm Chart definitions..."

# Create maduro/Chart.yaml
cat > helm/maduro/Chart.yaml <<EOF
apiVersion: v2
name: maduro
description: A Helm chart for Maduro
type: application
version: $VERSION
dependencies:
  - name: kmcp
    version: v0.0.1
    repository: oci://ghcr.io/kagent-dev/kmcp/helm
    condition: kmcp.enabled
  - name: maduro-tools
    version: 0.0.12
    repository: oci://ghcr.io/kagent-dev/tools/helm
    condition: kagent-tools.enabled
  - name: grafana-mcp
    version: 0.0.1
    repository: file://../tools/grafana-mcp
    condition: tools.grafana-mcp.enabled, agents.observability-agent.enabled
  - name: querydoc
    version: 0.0.1
    repository: file://../tools/querydoc
    condition: tools.querydoc.enabled
  - name: k8s-agent
    version: 0.0.1
    repository: file://../agents/k8s
    condition: agents.k8s-agent.enabled
  - name: kgateway-agent
    version: 0.0.1
    repository: file://../agents/kgateway
    condition: agents.kgateway-agent.enabled
  - name: istio-agent
    version: 0.0.1
    repository: file://../agents/istio
    condition: agents.istio-agent.enabled
  - name: promql-agent
    version: 0.0.1
    repository: file://../agents/promql
    condition: agents.promql-agent.enabled
  - name: observability-agent
    version: 0.0.1
    repository: file://../agents/observability
    condition: agents.observability-agent.enabled
  - name: argo-rollouts-agent
    version: 0.0.1
    repository: file://../agents/argo-rollouts
    condition: agents.argo-rollouts-agent.enabled
  - name: helm-agent
    version: 0.0.1
    repository: file://../agents/helm
    condition: agents.helm-agent.enabled
  - name: cilium-policy-agent
    version: 0.0.1
    repository: file://../agents/cilium-policy
    condition: agents.cilium-policy-agent.enabled
  - name: cilium-manager-agent
    version: 0.0.1
    repository: file://../agents/cilium-manager
    condition: agents.cilium-manager-agent.enabled
  - name: cilium-debug-agent
    version: 0.0.1
    repository: file://../agents/cilium-debug
    condition: agents.cilium-debug-agent.enabled
EOF

# Create maduro-crds/Chart.yaml
cat > helm/maduro-crds/Chart.yaml <<EOF
apiVersion: v2
name: maduro-crds
description: CRDs for maduro
type: application
version: $VERSION
dependencies:
  - name: kmcp-crds
    version: v0.0.1
    repository: oci://ghcr.io/kagent-dev/kmcp/helm
    condition: kmcp.enabled
EOF

echo "--> Chart.yaml files created successfully."

# 2. Build Docker Images
echo "--> Building Docker images..."

# Controller
docker build -t "$REGISTRY/$REPO/controller:$VERSION" -f go/Dockerfile ./go

# UI
docker build -t "$REGISTRY/$REPO/ui:$VERSION" -f ui/Dockerfile ./ui

# ADK
docker build -t "$REGISTRY/$REPO/kagent-adk:$VERSION" -f python/Dockerfile ./python
# Tag for local use
docker tag "$REGISTRY/$REPO/kagent-adk:$VERSION" "maduro-local/kagent-adk:$VERSION"

# App
docker build --build-arg KAGENT_ADK_VERSION=$VERSION \
    --build-arg DOCKER_REGISTRY="maduro-local" \
    --build-arg DOCKER_REPO="" \
    -t "$REGISTRY/$REPO/app:$VERSION" -f python/Dockerfile.app ./python

# 3. Load Images (if Kind) or Push
if command -v kind >/dev/null 2>&1; then
    echo "--> Loading images into Kind..."
    kind load docker-image "$REGISTRY/$REPO/controller:$VERSION" --name maduro || true
    kind load docker-image "$REGISTRY/$REPO/ui:$VERSION" --name maduro || true
    kind load docker-image "$REGISTRY/$REPO/kagent-adk:$VERSION" --name maduro || true
    kind load docker-image "$REGISTRY/$REPO/app:$VERSION" --name maduro || true
else
    echo "--> Not using Kind. Skipping image load."
fi

# 4. Install with Helm
echo "--> Updating Helm dependencies..."
helm dependency update helm/maduro
helm dependency update helm/maduro-crds

echo "--> Installing CRDs..."
helm upgrade --install ${RELEASE_NAME}-crds helm/maduro-crds \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --wait \
    --set kmcp.enabled=true

echo "--> Installing Maduro App..."
HELM_ARGS=""
if [ ! -z "$OPENAI_API_KEY" ]; then
    HELM_ARGS="$HELM_ARGS --set providers.openAI.apiKey=$OPENAI_API_KEY"
fi

helm upgrade --install ${RELEASE_NAME} helm/maduro \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --wait \
    --set ui.service.type=LoadBalancer \
    --set controller.service.type=LoadBalancer \
    --set imagePullPolicy=IfNotPresent \
    --set kmcp.enabled=true \
    $HELM_ARGS

echo "=== Installation Complete! ==="
