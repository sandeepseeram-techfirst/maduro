ARG KAGENT_ADK_VERSION=latest
ARG DOCKER_REGISTRY=ghcr.io
ARG DOCKER_REPO=kagent-dev/kagent

FROM $DOCKER_REGISTRY${DOCKER_REPO:+/}$DOCKER_REPO/kagent-adk:$KAGENT_ADK_VERSION

# Install kubectl (v1.29.0)
RUN curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install helm (v3.14.0)
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    HELM_INSTALL_DIR=/usr/local/bin ./get_helm.sh --version v3.14.0 && \
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