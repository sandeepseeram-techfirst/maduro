ARG KAGENT_ADK_VERSION=latest
ARG DOCKER_REGISTRY=ghcr.io
ARG DOCKER_REPO=kagent-dev/kagent
# Use a specific stage or name if we can't rely on the registry image being available during build context
# But standard pattern is to use the image we just built.
# The issue is that localhost:5001 is not accessible inside the build context or buildkit can't find it.
# We should probably build from source or rely on local image cache if possible, but FROM usually pulls.
# A trick is to use a relative reference if in same buildx context, but here they are separate builds.

FROM $DOCKER_REGISTRY${DOCKER_REPO:+/}$DOCKER_REPO/kagent-adk:$KAGENT_ADK_VERSION

# Install kubectl (hardcoded stable version to ensure build stability)
RUN curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install helm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh && \
    rm get_helm.sh

# Offline mode
ENV UV_OFFLINE=1

EXPOSE 8080
ARG VERSION

LABEL org.opencontainers.image.source=https://github.com/kagent-dev/kagent
LABEL org.opencontainers.image.description="Kagent app is the Kagent agent runtime for adk agents."
LABEL org.opencontainers.image.authors="Kagent Creators 🤖"
LABEL org.opencontainers.image.version="$VERSION"

ENTRYPOINT ["kagent-adk", "static"]
CMD ["--host", "0.0.0.0", "--port", "8080"]