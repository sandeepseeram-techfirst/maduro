#!/bin/bash
set -e

# =================================================================================================
# MADURO "FRESH START" DEPLOYMENT SCRIPT
# =================================================================================================
# This script rebuilds the entire application deployment artifacts from scratch.
# It forces a clean build to avoid cache issues.
# =================================================================================================

# Configuration
# -------------------------------------------------------------------------------------------------
RAND_ID=$(openssl rand -hex 4 2>/dev/null || echo "dev")
: "${REGISTRY:=ttl.sh/maduro-${RAND_ID}}"

VERSION="0.0.1"
# If using ttl.sh, we append -24h to the tag to set the retention period
if [[ "$REGISTRY" == *"ttl.sh"* ]]; then
    VERSION="${VERSION}-24h"
fi

KMCP_VERSION="v0.0.1"
REPO="maduro"
NAMESPACE="maduro"

echo "=================================================="
echo "   MADURO FRESH DEPLOYMENT - VERSION $VERSION"
echo "   Registry: $REGISTRY"
echo "=================================================="

# -------------------------------------------------------------------------------------------------
# 0. CLEANUP & PREP
# -------------------------------------------------------------------------------------------------
echo -e "\n[0/4] Cleaning up..."
# Force clear docker build cache for our targets to ensure file changes are picked up
echo "  -> Pruning specific build cache..."
docker builder prune -f --filter "label=org.opencontainers.image.version=$VERSION" > /dev/null 2>&1 || true

mkdir -p bin
export PATH="$PWD/bin:$PATH"

# Ensure Helm/Kubectl
if ! command -v helm &> /dev/null; then
    echo "  -> Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# -------------------------------------------------------------------------------------------------
# 1. PREPARE HELM CHARTS
# -------------------------------------------------------------------------------------------------
echo -e "\n[1/4] Preparing Helm Charts..."

# Helper to create Chart.yaml
create_chart_yaml() {
    local dir=$1
    local name=$(basename "$dir")
    cat > "$dir/Chart.yaml" <<EOF
apiVersion: v2
name: $name
description: Auto-generated chart for $name
type: application
version: $VERSION
appVersion: "$VERSION"
EOF
}

# Fix Charts
create_chart_yaml "helm/maduro"
create_chart_yaml "helm/maduro-crds"
for d in helm/agents/*; do [ -d "$d" ] && create_chart_yaml "$d"; done
for d in helm/tools/*; do [ -d "$d" ] && create_chart_yaml "$d"; done

# Ensure _helpers.tpl exists for agents
for d in helm/agents/*; do
    if [ -d "$d" ]; then
        mkdir -p "$d/templates"
        if [ ! -f "$d/templates/_helpers.tpl" ]; then
            cat > "$d/templates/_helpers.tpl" <<EOF
{{- define "kagent.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "kagent.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "kagent.defaultModelConfigName" -}}default-model-config{{- end -}}
EOF
        fi
    fi
done

# -------------------------------------------------------------------------------------------------
# 2. BUILD DOCKER IMAGES (NO CACHE)
# -------------------------------------------------------------------------------------------------
echo -e "\n[2/4] Building Docker Images (Clean Build)..."

build_image() {
    local name=$1
    local dockerfile=$2
    local context=$3
    local extra_args=$4
    local tag="$REGISTRY/$REPO/$name:$VERSION"
    
    echo "  -> Building $name ($tag)..."
    
    # Use --no-cache to force update
    if docker build --no-cache \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILDPLATFORM="linux/amd64" \
        --build-arg LDFLAGS="-X main.Version=$VERSION" \
        $extra_args \
        -t "$tag" -f "$dockerfile" "$context"; then
        echo "     [OK] Built $name"
    else
        echo "     [FAILED] Build failed for $name"
        exit 1
    fi
}

# Build Controller
build_image "controller" "go/Dockerfile" "go"

# Build UI
build_image "ui" "ui/Dockerfile" "ui"

# Build ADK
echo "  -> Building kagent-adk..."
build_image "kagent-adk" "python/Dockerfile" "python"

# Tag ADK for local reference
docker tag "$REGISTRY/$REPO/kagent-adk:$VERSION" "maduro-local/kagent-adk:$VERSION"

# Build App (Agent Runtime + Tools)
echo "  -> Building app..."
APP_ARGS="--build-arg KAGENT_ADK_VERSION=$VERSION --build-arg DOCKER_REGISTRY=maduro-local --build-arg DOCKER_REPO="
build_image "app" "python/Dockerfile.app" "python" "$APP_ARGS"

# -------------------------------------------------------------------------------------------------
# 3. PUSH IMAGES
# -------------------------------------------------------------------------------------------------
echo -e "\n[3/4] Pushing Images..."
docker push "$REGISTRY/$REPO/controller:$VERSION"
docker push "$REGISTRY/$REPO/ui:$VERSION"
docker push "$REGISTRY/$REPO/app:$VERSION"

# -------------------------------------------------------------------------------------------------
# 4. DEPLOY
# -------------------------------------------------------------------------------------------------
echo -e "\n[4/4] Deploying to Kubernetes..."

# Update dependencies
helm dependency update helm/maduro > /dev/null
helm dependency update helm/maduro-crds > /dev/null

# Install CRDs
helm upgrade --install maduro-crds helm/maduro-crds \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    --set kmcp.enabled=true

# Install App
# Note: We explicitly set kagentTools.image to our new 'app' image
helm upgrade --install maduro helm/maduro \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    --set ui.service.type=LoadBalancer \
    --set controller.service.type=LoadBalancer \
    --set imagePullPolicy=IfNotPresent \
    --set kmcp.enabled=true \
    --set controller.image.registry="" \
    --set controller.image.repository="$REGISTRY/$REPO/controller" \
    --set controller.image.tag="$VERSION" \
    --set ui.image.registry="" \
    --set ui.image.repository="$REGISTRY/$REPO/ui" \
    --set ui.image.tag="$VERSION" \
    --set controller.agentImage.registry="" \
    --set controller.agentImage.repository="$REGISTRY/$REPO/app" \
    --set controller.agentImage.tag="$VERSION" \
    --set kagentTools.image.registry="" \
    --set kagentTools.image.repository="$REGISTRY/$REPO/app" \
    --set kagentTools.image.tag="$VERSION" \
    --set global.tag="$VERSION" \
    --set registry="" \
    --set global.registry="" \
    --set global.image.registry="" \
    ${OPENAI_API_KEY:+--set providers.openAI.apiKey=$OPENAI_API_KEY}

# Install Agents
echo "  -> Installing Agents..."
for d in helm/agents/*; do
    if [ -d "$d" ]; then
        name=$(basename "$d")
        helm upgrade --install "$name" "$d" --namespace "$NAMESPACE" --wait > /dev/null 2>&1 || true
    fi
done

echo "=================================================="
echo "   DEPLOYMENT COMPLETE"
echo "=================================================="
