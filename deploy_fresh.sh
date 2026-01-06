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
VERSION="0.0.1"
KMCP_VERSION="v0.0.1"
# REGISTRY="localhost:5001" # DISABLED: We are building locally without a registry
REPO="maduro-dev/maduro"
NAMESPACE="maduro"

# ... (omitted)

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
    # IMPORTANT: Tagging WITHOUT registry prefix so Kubernetes finds it locally
    local tag="$REPO/$name:$VERSION"
    
    echo "  -> Building $name ($tag)..."
    
    # ... (rest of build_image function)
    if docker build \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILDPLATFORM="linux/amd64" \
        --build-arg LDFLAGS="-X main.Version=$VERSION" \
        $extra_args \
        -t "$tag" -f "$dockerfile" "$context" > "$log_file" 2>&1; then
        echo "     [OK] Built $name"
        rm "$log_file"
    else
        # ... (error handling)
    fi
}

# ... (rest of image building calls)

# Tag ADK for local reference in next build
# Note: We tag it with the local name we just built
docker tag "$REPO/kagent-adk:$VERSION" "maduro-local/kagent-adk:$VERSION"

# ...

# -------------------------------------------------------------------------------------------------
# 3. LOAD IMAGES (Kind/Local)
# -------------------------------------------------------------------------------------------------
echo -e "\n[3/4] Loading Images into Cluster..."

# DISABLED: Pushing to localhost:5001 is failing and not needed if we rely on local images
# echo "  -> Pushing images to local registry $REGISTRY..."
# docker push "$REGISTRY/$REPO/controller:$VERSION" || true
# docker push "$REGISTRY/$REPO/ui:$VERSION" || true
# docker push "$REGISTRY/$REPO/app:$VERSION" || true

if command -v kind >/dev/null 2>&1; then
    echo "  -> Kind detected. Loading images..."
    # Load the images we just built (without registry prefix)
    kind load docker-image "$REPO/controller:$VERSION" --name maduro || true
    kind load docker-image "$REPO/ui:$VERSION" --name maduro || true
    kind load docker-image "$REPO/kagent-adk:$VERSION" --name maduro || true
    kind load docker-image "$REPO/app:$VERSION" --name maduro || true
else
    echo "  -> Kind not detected. Skipping direct load."
    echo "     WARNING: If you are using Minikube or a remote cluster, you must manually load or push images."
    echo "     For Minikube: eval \$(minikube docker-env) before running this script."
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
    --set controller.image.repository="maduro-dev/maduro/controller" \
    --set controller.image.tag="$VERSION" \
    --set ui.image.registry="" \
    --set ui.image.repository="maduro-dev/maduro/ui" \
    --set ui.image.tag="$VERSION" \
    --set controller.agentImage.registry="" \
    --set controller.agentImage.repository="maduro-dev/maduro/app" \
    --set controller.agentImage.tag="$VERSION" \
    --set global.tag="$VERSION" \
    --set global.registry="" \
    $HELM_ARGS

echo "=================================================="
echo "   DEPLOYMENT SUCCESSFUL"
echo "=================================================="
echo "Check pods with: kubectl get pods -n $NAMESPACE"
