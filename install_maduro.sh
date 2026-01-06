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
echo "Generating Helm charts..."
export VERSION=$VERSION
export KMCP_VERSION=$KMCP_VERSION

# We use python to simulate envsubst if it's not available, or just assume envsubst is there (standard in many environments, but maybe not windows git bash)
# Let's try to use a simple sed or just python for reliability if envsubst is missing.
# For now, let's assume envsubst or simple cp if vars are not critical for basic test.
# Actually, the VERSION is important.

    # Try envsubst first, then python3, then python
    # We need to export variables for python to pick them up via os.environ if not using envsubst
    export VERSION
    export KMCP_VERSION

    if command -v envsubst >/dev/null 2>&1; then
        echo "Using envsubst for template substitution..."
        if [ -f "$ROOT_DIR/helm/maduro-crds/Chart-template.yaml" ]; then
             envsubst < "$ROOT_DIR/helm/maduro-crds/Chart-template.yaml" > "$ROOT_DIR/helm/maduro-crds/Chart.yaml"
        else
             echo "Warning: $ROOT_DIR/helm/maduro-crds/Chart-template.yaml not found."
        fi
        
        if [ -f "$ROOT_DIR/helm/maduro/Chart-template.yaml" ]; then
            envsubst < "$ROOT_DIR/helm/maduro/Chart-template.yaml" > "$ROOT_DIR/helm/maduro/Chart.yaml"
        else
            echo "Warning: $ROOT_DIR/helm/maduro/Chart-template.yaml not found."
        fi

    elif command -v python3 >/dev/null 2>&1; then
        echo "envsubst not found, using python3 fallback..."
        if [ -f "$ROOT_DIR/helm/maduro-crds/Chart-template.yaml" ]; then
            python3 -c "import os,sys; content=sys.stdin.read(); print(content.replace('\${VERSION}', os.environ.get('VERSION', '0.0.1')).replace('\${KMCP_VERSION}', os.environ.get('KMCP_VERSION', 'v0.0.1')))" < "$ROOT_DIR/helm/maduro-crds/Chart-template.yaml" > "$ROOT_DIR/helm/maduro-crds/Chart.yaml"
        else
             # If template is missing, maybe Chart.yaml is already there (e.g. from repo)
             echo "Warning: $ROOT_DIR/helm/maduro-crds/Chart-template.yaml not found. Assuming Chart.yaml exists."
        fi
        
        if [ -f "$ROOT_DIR/helm/maduro/Chart-template.yaml" ]; then
            python3 -c "import os,sys; content=sys.stdin.read(); print(content.replace('\${VERSION}', os.environ.get('VERSION', '0.0.1')).replace('\${KMCP_VERSION}', os.environ.get('KMCP_VERSION', 'v0.0.1')))" < "$ROOT_DIR/helm/maduro/Chart-template.yaml" > "$ROOT_DIR/helm/maduro/Chart.yaml"
        else
             echo "Warning: $ROOT_DIR/helm/maduro/Chart-template.yaml not found. Assuming Chart.yaml exists."
        fi
    else
        echo "envsubst and python3 not found, using python fallback..."
        if [ -f "$ROOT_DIR/helm/maduro-crds/Chart-template.yaml" ]; then
            python -c "import os,sys; content=sys.stdin.read(); print(content.replace('\${VERSION}', os.environ.get('VERSION', '0.0.1')).replace('\${KMCP_VERSION}', os.environ.get('KMCP_VERSION', 'v0.0.1')))" < "$ROOT_DIR/helm/maduro-crds/Chart-template.yaml" > "$ROOT_DIR/helm/maduro-crds/Chart.yaml"
        else
             # If template is missing, maybe Chart.yaml is already there (e.g. from repo)
             echo "Warning: $ROOT_DIR/helm/maduro-crds/Chart-template.yaml not found. Assuming Chart.yaml exists."
        fi
        
        if [ -f "$ROOT_DIR/helm/maduro/Chart-template.yaml" ]; then
            python -c "import os,sys; content=sys.stdin.read(); print(content.replace('\${VERSION}', os.environ.get('VERSION', '0.0.1')).replace('\${KMCP_VERSION}', os.environ.get('KMCP_VERSION', 'v0.0.1')))" < "$ROOT_DIR/helm/maduro/Chart-template.yaml" > "$ROOT_DIR/helm/maduro/Chart.yaml"
        else
             echo "Warning: $ROOT_DIR/helm/maduro/Chart-template.yaml not found. Assuming Chart.yaml exists."
        fi
    fi

# Update dependencies
echo "Updating Helm dependencies..."
# Ensure Chart.yaml exists before updating dependencies
if [ ! -f "$ROOT_DIR/helm/maduro/Chart.yaml" ]; then
    echo "Error: $ROOT_DIR/helm/maduro/Chart.yaml not found. Template substitution might have failed."
    exit 1
fi
if [ ! -f "$ROOT_DIR/helm/maduro-crds/Chart.yaml" ]; then
    echo "Error: $ROOT_DIR/helm/maduro-crds/Chart.yaml not found. Template substitution might have failed."
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
