# Deploying Maduro to Your Cluster

Since you have pushed your code to GitHub, you can now deploy it to your Kubernetes cluster (e.g., via the iximiuz.com shell or any other terminal with access to your cluster).

## Step 1: Clone the Repository

In your cluster's terminal, run:

```bash
git clone https://github.com/sandeepseeram-techfirst/maduro.git
cd maduro
```

## Step 2: Build and Install

We have prepared a script that builds the Docker images locally (inside your cluster environment) and installs the Helm chart.

**Note:** This script assumes your environment has `docker` (or a compatible builder) and `helm` installed.

1.  **Make the scripts executable:**

    ```bash
    chmod +x linux_build_install.sh install_maduro.sh
    ```

2.  **Run the installation script:**

    ```bash
    ./linux_build_install.sh
    ```

    *   The script will verify dependencies.
    *   It will build the necessary Docker images.
    *   **It will prompt you for your OpenAI API Key** (since you requested to use OpenAI).
    *   It will install the `maduro` Helm chart.

## Step 3: Access the UI

Once the installation is complete, check the services to get the URL:

```bash
kubectl get svc -n maduro
```

*   Look for `maduro-ui`.
*   If it has an `EXTERNAL-IP`, you can access it at `http://<EXTERNAL-IP>:8080` (or port 80 depending on configuration).
*   If you are in a constrained environment without LoadBalancer support, you can port-forward:

    ```bash
    kubectl port-forward -n maduro svc/maduro-ui 8080:8080
    ```

## Troubleshooting

*   **Images not found?**
    If the cluster cannot find the images, it might be because the local registry isn't configured as expected. The script defaults to `localhost:5001`. You can override this:
    ```bash
    export REGISTRY="my-registry.io"
    ./linux_build_install.sh
    ```

*   **API Key issues?**
    You can manually export the key before running the script:
    ```bash
    export OPENAI_API_KEY="sk-..."
    ./linux_build_install.sh
    ```
