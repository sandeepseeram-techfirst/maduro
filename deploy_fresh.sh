#!/bin/bash
set -e

# =================================================================================================
# MADURO "FRESH START" DEPLOYMENT SCRIPT
# =================================================================================================
# This script rebuilds the entire application deployment artifacts from scratch.
# It bypasses existing fragile scripts and template generation logic to ensure a stable install.
#
# Usage: ./deploy_fresh.sh
# =================================================================================================

# Configuration
# -------------------------------------------------------------------------------------------------
# PUBLIC REGISTRY SETUP (ttl.sh)
# -------------------------------------------------------------------------------------------------
# We default to ttl.sh, an ephemeral public registry that requires no login.
# This solves the "pull access denied" and "image not found" errors by making images publicly available.
# To use your own registry (e.g. Docker Hub), run: export REGISTRY=docker.io/yourusername
RAND_ID=$(openssl rand -hex 4 2>/dev/null || echo "dev")
: "${REGISTRY:=ttl.sh/maduro-${RAND_ID}}"

VERSION="0.0.1"
# If using ttl.sh, we append -24h to the tag to set the retention period (default behavior of ttl.sh)
if [[ "$REGISTRY" == *"ttl.sh"* ]]; then
    VERSION="${VERSION}-24h"
fi

KMCP_VERSION="v0.0.1"
REPO="maduro" # Simplified repo path
NAMESPACE="maduro"

echo "=================================================="
echo "   MADURO FRESH DEPLOYMENT - VERSION $VERSION"
echo "   Registry: $REGISTRY"
echo "=================================================="

# -------------------------------------------------------------------------------------------------
# 0. CHECK DEPENDENCIES & SETUP LOCAL TOOLS
# -------------------------------------------------------------------------------------------------
echo -e "\n[0/4] Checking Dependencies..."

mkdir -p bin
export PATH="$PWD/bin:$PATH"

# Check/Install Helm
if ! command -v helm &> /dev/null; then
    echo "  -> Helm not found. Downloading local copy..."
    # Detect OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # Map architectures
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac
    
    # Handle Windows/GitBash/WSL
    if [[ "$OS" == *"mingw"* ]] || [[ "$OS" == *"cygwin"* ]] || [[ "$OS" == *"msys"* ]]; then
        OS="windows"
        EXT=".zip"
    elif [[ "$OS" == "darwin" ]]; then
        OS="darwin"
        EXT=".tar.gz"
    else
        OS="linux" # Assume linux for others
        EXT=".tar.gz"
    fi

    HELM_URL="https://get.helm.sh/helm-v3.16.2-${OS}-${ARCH}${EXT}"
    echo "     Downloading from $HELM_URL"
    
    curl -fsSL "$HELM_URL" -o helm-dist${EXT}
    
    if [[ "$OS" == "windows" ]]; then
        unzip -o helm-dist${EXT} > /dev/null
        mv ${OS}-${ARCH}/helm.exe bin/helm
    else
        tar -zxvf helm-dist${EXT} > /dev/null
        mv ${OS}-${ARCH}/helm bin/helm
    fi
    
    chmod +x bin/helm
    rm -rf ${OS}-${ARCH} helm-dist${EXT}
    echo "  -> Helm installed to ./bin/helm"
else
    echo "  -> Helm found: $(helm version --short)"
fi

# Check/Install Kubectl (if missing)
if ! command -v kubectl &> /dev/null; then
    # Detect OS (Redetect for kubectl block scope if needed, or just reuse)
    # Ensure variables are set if they were skipped in helm block
    if [ -z "$OS" ]; then
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        ARCH=$(uname -m)
        case $ARCH in
            x86_64) ARCH="amd64" ;;
            aarch64) ARCH="arm64" ;;
        esac
        if [[ "$OS" == *"mingw"* ]] || [[ "$OS" == *"cygwin"* ]] || [[ "$OS" == *"msys"* ]]; then
            OS="windows"
        fi
    fi

    echo "  -> Kubectl not found. Downloading local copy..."
    KUBECTL_URL="https://dl.k8s.io/release/v1.29.0/bin/${OS}/${ARCH}/kubectl"
    # Fix URL construction for windows (dl.k8s.io is sensitive)
    if [[ "$OS" == "windows" ]]; then
        # The official windows binary path is just "kubectl.exe", but the OS/Arch part is standard.
        # Let's verify standard path: https://dl.k8s.io/release/v1.29.0/bin/windows/amd64/kubectl.exe
        KUBECTL_URL="https://dl.k8s.io/release/v1.29.0/bin/windows/amd64/kubectl.exe"
        echo "     Downloading from $KUBECTL_URL"
        curl -fsSL "$KUBECTL_URL" -o bin/kubectl.exe
    else
        echo "     Downloading from $KUBECTL_URL"
        curl -fsSL "$KUBECTL_URL" -o bin/kubectl
    fi
    chmod +x bin/kubectl*
    echo "  -> Kubectl installed to ./bin/kubectl"
else
    echo "  -> Kubectl found: $(kubectl version --client --short 2>/dev/null || echo 'ok')"
fi

# -------------------------------------------------------------------------------------------------
# 1. FIX HELM CHARTS
# -------------------------------------------------------------------------------------------------
echo -e "\n[1/4] Normalizing Helm Charts..."

# Function to generate static Chart.yaml from template or default
generate_chart_yaml() {
    local dir=$1
    local name=$(basename "$dir")
    local type=$2 # "application" or "library" (defaults to application)
    
    # Define output file
    local chart_file="$dir/Chart.yaml"
    
    echo "Processing $name..."
    
    # If Chart-template.yaml exists, use it as base but replace variables manually
    if [ -f "$dir/Chart-template.yaml" ]; then
        # Read template, replace vars, write to Chart.yaml
        sed "s/\${VERSION}/$VERSION/g" "$dir/Chart-template.yaml" | \
        sed "s/\${KMCP_VERSION}/$KMCP_VERSION/g" > "$chart_file"
    else
        # If no template, create a basic standard Chart.yaml
        cat > "$chart_file" <<EOF
apiVersion: v2
name: $name
description: Auto-generated chart for $name
type: application
version: $VERSION
appVersion: "$VERSION"
EOF
    fi
    
    # Ensure it was created
    if [ ! -f "$chart_file" ]; then
        echo "Error: Failed to create $chart_file"
        exit 1
    fi
}

# Fix Main Charts
echo "  -> Processing Main Charts..."
generate_chart_yaml "helm/maduro"
generate_chart_yaml "helm/maduro-crds"

# Fix Agent Charts
echo "  -> Processing Agent Charts..."
for d in helm/agents/*; do
    if [ -d "$d" ]; then
        generate_chart_yaml "$d"
        
        # Create _helpers.tpl if missing (required for kagent.* templates)
        mkdir -p "$d/templates"
        if [ ! -f "$d/templates/_helpers.tpl" ]; then
            echo "     Creating _helpers.tpl for $(basename "$d")..."
            cat > "$d/templates/_helpers.tpl" <<EOF
{{/*
Expand the namespace of the release.
*/}}
{{- define "kagent.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "kagent.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Default model config name
*/}}
{{- define "kagent.defaultModelConfigName" -}}
default-model-config
{{- end -}}
EOF
        fi
    fi
done

# Fix Tool Charts
echo "  -> Processing Tool Charts..."
for d in helm/tools/*; do
    if [ -d "$d" ]; then
        generate_chart_yaml "$d"
    fi
done

echo "  -> All Helm charts normalized."


# -------------------------------------------------------------------------------------------------
# 2. BUILD DOCKER IMAGES
# -------------------------------------------------------------------------------------------------
echo -e "\n[2/4] Building Docker Images..."

# Helper function to build images with common args
build_image() {
    local name=$1
    local dockerfile=$2
    local context=$3
    local extra_args=$4
    # IMPORTANT: Tagging with registry to allow push
    local tag="$REGISTRY/$REPO/$name:$VERSION"
    
    echo "  -> Building $name ($tag)..."
    
    # Capture output to log file for debugging
    local log_file="build_${name}.log"
    
    # We use 'eval' for extra_args to properly handle spaces/quotes if any
    if docker build \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILDPLATFORM="linux/amd64" \
        --build-arg LDFLAGS="-X main.Version=$VERSION" \
        $extra_args \
        -t "$tag" -f "$dockerfile" "$context" > "$log_file" 2>&1; then
        echo "     [OK] Built $name"
        rm "$log_file"
    else
        echo "     [FAILED] Build failed for $name. Check $log_file for details."
        echo "     Last 10 lines of log:"
        tail -n 10 "$log_file"
        exit 1
    fi
}

# Build Controller
build_image "controller" "go/Dockerfile" "go"

# Build UI
build_image "ui" "ui/Dockerfile" "ui"

# Build ADK (needed for App)
echo "  -> Building kagent-adk..."
build_image "kagent-adk" "python/Dockerfile" "python"

# Tag ADK for local reference in next build
docker tag "$REGISTRY/$REPO/kagent-adk:$VERSION" "maduro-local/kagent-adk:$VERSION"

# Build App
echo "  -> Building app..."
# Note: Dockerfile.app needs KAGENT_ADK_VERSION etc.
APP_ARGS="--build-arg KAGENT_ADK_VERSION=$VERSION --build-arg DOCKER_REGISTRY=maduro-local --build-arg DOCKER_REPO="
build_image "app" "python/Dockerfile.app" "python" "$APP_ARGS"

echo "  -> All images built successfully."


# -------------------------------------------------------------------------------------------------
# 3. PUSH IMAGES (Required for remote/ttl.sh)
# -------------------------------------------------------------------------------------------------
echo -e "\n[3/4] Pushing Images to Registry..."

echo "  -> Pushing images to $REGISTRY..."
docker push "$REGISTRY/$REPO/controller:$VERSION"
docker push "$REGISTRY/$REPO/ui:$VERSION"
docker push "$REGISTRY/$REPO/app:$VERSION"

if command -v kind >/dev/null 2>&1; then
    echo "  -> Kind detected. Loading images just in case (optimization)..."
    # Load the images we just built
    kind load docker-image "$REGISTRY/$REPO/controller:$VERSION" --name maduro || true
    kind load docker-image "$REGISTRY/$REPO/ui:$VERSION" --name maduro || true
    kind load docker-image "$REGISTRY/$REPO/kagent-adk:$VERSION" --name maduro || true
    kind load docker-image "$REGISTRY/$REPO/app:$VERSION" --name maduro || true
fi


# -------------------------------------------------------------------------------------------------
# 4. DEPLOY WITH HELM
# -------------------------------------------------------------------------------------------------
echo -e "\n[4/4] Deploying to Kubernetes..."

# Update dependencies
echo "  -> Updating Helm dependencies..."
helm dependency update helm/maduro > /dev/null
helm dependency update helm/maduro-crds > /dev/null

# Install CRDs
echo "  -> Installing CRDs..."
helm upgrade --install maduro-crds helm/maduro-crds \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    --set kmcp.enabled=true > /dev/null

# Install App
echo "  -> Installing Maduro Application..."

# Prepare arguments
HELM_ARGS=""
if [ ! -z "$OPENAI_API_KEY" ]; then
    HELM_ARGS="$HELM_ARGS --set providers.openAI.apiKey=$OPENAI_API_KEY"
fi

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
    --set controller.image.pullPolicy="IfNotPresent" \
    --set ui.image.registry="" \
    --set ui.image.repository="$REGISTRY/$REPO/ui" \
    --set ui.image.tag="$VERSION" \
    --set ui.image.pullPolicy="IfNotPresent" \
    --set controller.agentImage.registry="" \
    --set controller.agentImage.repository="$REGISTRY/$REPO/app" \
    --set controller.agentImage.tag="$VERSION" \
    --set controller.agentImage.pullPolicy="IfNotPresent" \
    --set global.tag="$VERSION" \
    --set registry="" \
    --set global.registry="" \
    --set global.image.registry="" \
    $HELM_ARGS

# Install Agents
echo "  -> Installing Agents..."
for d in helm/agents/*; do
    if [ -d "$d" ]; then
        name=$(basename "$d")
        echo "     Installing agent: $name..."
        helm upgrade --install "$name" "$d" \
            --namespace "$NAMESPACE" \
            --wait \
            --set image.registry="$REGISTRY" \
            --set image.repository="$REPO/$name" \
            --set image.tag="$VERSION" \
            > /dev/null 2>&1 || echo "     [WARNING] Failed to install agent $name (continuing...)"
    fi
done

# Install Tools
echo "  -> Installing Tools..."
for d in helm/tools/*; do
    if [ -d "$d" ]; then
        name=$(basename "$d")
        echo "     Installing tool: $name..."
        helm upgrade --install "$name" "$d" \
            --namespace "$NAMESPACE" \
            --wait \
            --set image.registry="$REGISTRY" \
            --set image.repository="$REPO/$name" \
            --set image.tag="$VERSION" \
            > /dev/null 2>&1 || echo "     [WARNING] Failed to install tool $name (continuing...)"
    fi
done

echo "=================================================="
echo "   DEPLOYMENT SUCCESSFUL"
echo "=================================================="
echo "Check pods with: kubectl get pods -n $NAMESPACE"
