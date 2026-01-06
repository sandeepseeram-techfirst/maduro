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
    
    # App
    echo "Building App..."
    docker build --build-arg KAGENT_ADK_VERSION=$VERSION --build-arg DOCKER_REGISTRY=$REGISTRY \
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
export VERSION=$VERSION
bash install_maduro.sh
