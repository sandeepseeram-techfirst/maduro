#!/bin/bash
set -e

# =================================================================================================
# MADURO V2 DEPLOYMENT SCRIPT (CLEAN SLATE)
# =================================================================================================

# Configuration
# Use timestamp to guarantee unique registry per deployment, forcing image pulls
RAND_ID=$(date +%s)
REGISTRY="ttl.sh/maduro-v2-${RAND_ID}"
VERSION="0.0.1-24h"
NAMESPACE="maduro"

echo "=================================================="
echo "   MADURO V2 DEPLOYMENT - CLEAN SLATE"
echo "   Registry: $REGISTRY"
echo "   Version:  $VERSION"
echo "=================================================="

# 1. BUILD IMAGES
# We use the root directory as context, but point to deploy_v2 Dockerfiles
echo -e "\n[1/4] Building Images..."

# Helper
build_push() {
    local name=$1
    local dockerfile=$2
    local context="."
    local tag="$REGISTRY/$name:$VERSION"
    
    echo "  -> Building $name..."
    # --no-cache is MANDATORY
    docker build --no-cache -t "$tag" -f "$dockerfile" "$context"
    
    echo "  -> Pushing $name..."
    docker push "$tag"
}

# Build Controller
build_push "controller" "deploy_v2/Dockerfile.controller"

# Build UI
build_push "ui" "deploy_v2/Dockerfile.ui"

# Build App (Combined Runtime + Tools)
build_push "app" "deploy_v2/Dockerfile.app"


# 2. GENERATE HELM VALUES
echo -e "\n[2/4] Generating Helm Values..."
cat > deploy_v2/values-override.yaml <<EOF
global:
  tag: "$VERSION"
  registry: ""
  image:
    registry: ""

controller:
  image:
    registry: ""
    repository: "$REGISTRY/controller"
    tag: "$VERSION"
  agentImage:
    registry: ""
    repository: "$REGISTRY/app"
    tag: "$VERSION"
  service:
    type: LoadBalancer

ui:
  image:
    registry: ""
    repository: "$REGISTRY/ui"
    tag: "$VERSION"
  service:
    type: LoadBalancer

kagentTools:
  enabled: true
  image:
    registry: ""
    repository: "$REGISTRY/app"
    tag: "$VERSION"
  
kmcp:
  enabled: true

providers:
  openAI:
    apiKey: "${OPENAI_API_KEY}"
EOF

# 3. DEPLOY
echo -e "\n[3/4] Deploying..."

# Ensure deps
helm dependency update helm/maduro > /dev/null
helm dependency update helm/maduro-crds > /dev/null

# Install CRDs
helm upgrade --install maduro-crds helm/maduro-crds \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    --set kmcp.enabled=true

# Install Main Chart
helm upgrade --install maduro helm/maduro \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    -f deploy_v2/values-override.yaml

# Install Agents
echo "  -> Installing Agents..."
for d in helm/agents/*; do
    if [ -d "$d" ]; then
        name=$(basename "$d")
        helm upgrade --install "$name" "$d" --namespace "$NAMESPACE" --wait > /dev/null 2>&1 || true
    fi
done

echo "=================================================="
echo "   DEPLOYMENT V2 COMPLETE"
echo "=================================================="
