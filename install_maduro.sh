#!/bin/bash
set -e

# Configuration
NAMESPACE=${NAMESPACE:-"maduro"}
RELEASE_NAME=${RELEASE_NAME:-"maduro"}
VERSION=${VERSION:-"0.0.1"}
KMCP_VERSION=${KMCP_VERSION:-"v0.0.1"} # You might need to adjust this default or fetch it
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$SCRIPT_DIR

echo "Installing Maduro to namespace: $NAMESPACE"

# Note: This script assumes images are already built and available in the cluster/registry.
# If you need to build images, please refer to install_maduro.ps1 or run 'make build' first.

# Check dependencies
command -v helm >/dev/null 2>&1 || { echo >&2 "I require helm but it's not installed.  Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "I require kubectl but it's not installed.  Aborting."; exit 1; }

# Generate Chart.yaml from templates
# echo "Generating Helm charts..."
# Skipping template generation as we are using static Chart.yaml files now.
# This avoids issues with envsubst/python missing in minimal environments.

# Update dependencies
echo "Updating Helm dependencies..."
# Ensure Chart.yaml exists before updating dependencies
if [ ! -f "$ROOT_DIR/helm/maduro/Chart.yaml" ]; then
    echo "Error: $ROOT_DIR/helm/maduro/Chart.yaml not found. This file should be present in the repository."
    exit 1
fi
if [ ! -f "$ROOT_DIR/helm/maduro-crds/Chart.yaml" ]; then
    echo "Error: $ROOT_DIR/helm/maduro-crds/Chart.yaml not found. This file should be present in the repository."
    exit 1
fi

helm dependency update "$ROOT_DIR/helm/maduro"
helm dependency update "$ROOT_DIR/helm/maduro-crds"

# Install CRDs
echo "Installing Maduro CRDs..."
helm upgrade --install ${RELEASE_NAME}-crds "$ROOT_DIR/helm/maduro-crds" \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --wait \
    --set kmcp.enabled=true

# Install Maduro
echo "Installing Maduro..."
# Note: You might need to provide API keys via environment variables or flags
# e.g., OPENAI_API_KEY
# We'll check for them and pass them if set.

HELM_ARGS=""
if [ ! -z "$OPENAI_API_KEY" ]; then
    HELM_ARGS="$HELM_ARGS --set providers.openAI.apiKey=$OPENAI_API_KEY"
fi
if [ ! -z "$ANTHROPIC_API_KEY" ]; then
    HELM_ARGS="$HELM_ARGS --set providers.anthropic.apiKey=$ANTHROPIC_API_KEY"
fi

# Default to IfNotPresent for safer local development, unless explicitly set
IMAGE_PULL_POLICY=${IMAGE_PULL_POLICY:-"IfNotPresent"}

helm upgrade --install ${RELEASE_NAME} "$ROOT_DIR/helm/maduro" \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --wait \
    --set ui.service.type=LoadBalancer \
    --set controller.service.type=LoadBalancer \
    --set imagePullPolicy=$IMAGE_PULL_POLICY \
    --set controller.image.pullPolicy=$IMAGE_PULL_POLICY \
    --set ui.image.pullPolicy=$IMAGE_PULL_POLICY \
    --set kmcp.enabled=true \
    $HELM_ARGS

echo "Maduro installed successfully!"
echo "Check services with: kubectl get svc -n $NAMESPACE"
