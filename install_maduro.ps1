param(
    [string]$Version = "v0.0.1",
    [string]$Registry = "localhost:5001",
    [string]$Repo = "maduro-dev/maduro",
    [string]$Namespace = "maduro",
    [string]$KubeContext = "kind-maduro",
    [string]$OpenAIKey = ""
)

$ErrorActionPreference = "Stop"

# Helper function to check command existence
function Test-Command {
    param($Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "$Name is required but not found. Please install it."
        exit 1
    }
}

# 1. Prerequisites Check
Write-Host "Checking prerequisites..." -ForegroundColor Cyan
Test-Command "docker"
Test-Command "helm"
Test-Command "kubectl"

# 2. Build Docker Images
Write-Host "Building Docker images..." -ForegroundColor Cyan

# Define image names
$ControllerImage = "$Registry/$Repo/controller:$Version"
$UiImage = "$Registry/$Repo/ui:$Version"
$AppImage = "$Registry/$Repo/app:$Version"
$AdkImage = "$Registry/$Repo/kagent-adk:$Version"

# Build Controller
Write-Host "Building Controller: $ControllerImage"
docker build -t $ControllerImage -f go/Dockerfile ./go
if ($LASTEXITCODE -ne 0) { exit 1 }

# Build UI
Write-Host "Building UI: $UiImage"
docker build -t $UiImage -f ui/Dockerfile ./ui
if ($LASTEXITCODE -ne 0) { exit 1 }

# Build ADK
Write-Host "Building ADK: $AdkImage"
docker build -t $AdkImage -f python/Dockerfile ./python
if ($LASTEXITCODE -ne 0) { exit 1 }

# Build App
Write-Host "Building App: $AppImage"
docker build --build-arg KAGENT_ADK_VERSION=$Version --build-arg DOCKER_REGISTRY=$Registry -t $AppImage -f python/Dockerfile.app ./python
if ($LASTEXITCODE -ne 0) { exit 1 }

# 3. Push Images (Required for Kind or Remote Cluster)
Write-Host "Pushing images to registry..." -ForegroundColor Cyan
docker push $ControllerImage
docker push $UiImage
docker push $AdkImage
docker push $AppImage

# 4. Generate Helm Charts
Write-Host "Generating Helm charts..." -ForegroundColor Cyan

# Ensure output directory exists
if (-not (Test-Path "helm/maduro/Chart.yaml")) {
    # Simple replacement if envsubst is missing (PowerShell way)
    $ChartTemplate = Get-Content "helm/maduro/Chart-template.yaml" -Raw
    $ChartContent = $ChartTemplate.Replace('${VERSION}', $Version).Replace('${KMCP_VERSION}', 'v0.0.1')
    Set-Content -Path "helm/maduro/Chart.yaml" -Value $ChartContent
}

if (-not (Test-Path "helm/maduro-crds/Chart.yaml")) {
    $ChartTemplate = Get-Content "helm/maduro-crds/Chart-template.yaml" -Raw
    $ChartContent = $ChartTemplate.Replace('${VERSION}', $Version).Replace('${KMCP_VERSION}', 'v0.0.1')
    Set-Content -Path "helm/maduro-crds/Chart.yaml" -Value $ChartContent
}

# Update dependencies
helm dependency update helm/maduro
helm dependency update helm/maduro-crds

# 5. Install to Kubernetes
Write-Host "Installing to Kubernetes context: $KubeContext, Namespace: $Namespace" -ForegroundColor Cyan

# Install CRDs
helm upgrade --install maduro-crds helm/maduro-crds `
    --namespace $Namespace `
    --create-namespace `
    --wait `
    --kube-context $KubeContext `
    --set kmcp.enabled=true

# Install Maduro
$HelmArgs = @(
    "--namespace", $Namespace,
    "--create-namespace",
    "--wait",
    "--kube-context", $KubeContext,
    "--set", "ui.service.type=LoadBalancer",
    "--set", "registry=$Registry",
    "--set", "tag=$Version",
    "--set", "kmcp.enabled=true"
)

if (-not [string]::IsNullOrEmpty($OpenAIKey)) {
    $HelmArgs += "--set"
    $HelmArgs += "providers.openAI.apiKey=$OpenAIKey"
}

helm upgrade --install maduro helm/maduro @HelmArgs

Write-Host "Installation completed successfully!" -ForegroundColor Green
Write-Host "You can access the UI by getting the service IP:"
Write-Host "kubectl get svc -n $Namespace"
