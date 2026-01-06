#!/bin/bash
set -e

# Configuration
VERSION=${VERSION:-"v0.0.1"}
REGISTRY=${REGISTRY:-"localhost:5001"}
REPO=${REPO:-"maduro-dev/maduro"}
NAMESPACE=${NAMESPACE:-"maduro"}

# Helper function to build images
build_images() {
    echo "Building Docker images (Version: $VERSION)..."
    
    # Controller
    echo "Building Controller..."
    docker build -t "$REGISTRY/$REPO/controller:$VERSION" -f go/Dockerfile ./go
    
    # UI
    echo "Building UI..."
    docker build -t "$REGISTRY/$REPO/ui:$VERSION" -f ui/Dockerfile ./ui
    
    # ADK
    echo "Building ADK..."
    docker build -t "$REGISTRY/$REPO/kagent-adk:$VERSION" -f python/Dockerfile ./python

    # Push ADK immediately if local registry is used, to make it available for App build
    # Or, rely on local cache if registry is localhost but builder is not finding it.
    # The error "dial tcp 127.0.0.1:5001: connect: connection refused" suggests the build container 
    # cannot reach the registry on localhost.
    # We will tag ADK as a local image name that doesn't require registry lookup for the next step,
    # OR we try to push it if registry is available. 
    # BUT, since we are inside a cluster/node, maybe localhost:5001 is not running.
    # Let's simply tag it with a local name and pass that to the next build.
    
    LOCAL_ADK_TAG="maduro-local/kagent-adk:$VERSION"
    docker tag "$REGISTRY/$REPO/kagent-adk:$VERSION" "$LOCAL_ADK_TAG"
    
    # App
    echo "Building App..."
    # We pass the local tag components to the build args
    docker build --build-arg KAGENT_ADK_VERSION=$VERSION \
        --build-arg DOCKER_REGISTRY="maduro-local" \
        --build-arg DOCKER_REPO="" \
        -t "$REGISTRY/$REPO/app:$VERSION" -f python/Dockerfile.app ./python
}

# 1. Build
build_images

# 2. Push (Optional - if REGISTRY is not localhost or if using remote cluster)
# Check if we should push. 
# Logic: If registry is localhost, we might be in Kind or Minikube.
# If Kind, we might need 'kind load'.
# If remote cluster, we MUST push.

if [[ "$REGISTRY" != "localhost"* ]] && [[ "$REGISTRY" != "127.0.0.1"* ]]; then
    echo "Pushing images to $REGISTRY..."
    docker push "$REGISTRY/$REPO/controller:$VERSION"
    docker push "$REGISTRY/$REPO/ui:$VERSION"
    docker push "$REGISTRY/$REPO/kagent-adk:$VERSION"
    docker push "$REGISTRY/$REPO/app:$VERSION"
else
    echo "Registry is local. Skipping push (assuming local runtime or side-loaded)."
    # Optional: If using kind, try to load
    if command -v kind >/dev/null 2>&1; then
        echo "Detected 'kind'. Attempting to load images..."
        kind load docker-image "$REGISTRY/$REPO/controller:$VERSION" --name maduro || true
        kind load docker-image "$REGISTRY/$REPO/ui:$VERSION" --name maduro || true
        kind load docker-image "$REGISTRY/$REPO/kagent-adk:$VERSION" --name maduro || true
        kind load docker-image "$REGISTRY/$REPO/app:$VERSION" --name maduro || true
    fi
fi

# 3. Install
echo "Installing Maduro..."

# Prompt for OpenAI Key if not set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "OPENAI_API_KEY is not set."
    read -p "Enter your OpenAI API Key (or press Enter to skip/use default provider): " input_key
    if [ ! -z "$input_key" ]; then
        export OPENAI_API_KEY=$input_key
    fi
fi

export VERSION=$VERSION
bash install_maduro.sh
