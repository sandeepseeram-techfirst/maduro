import json
import subprocess
import logging
from typing import Optional, List, Dict, Any
from mcp.server.fastmcp import FastMCP

# Initialize FastMCP Server
mcp = FastMCP("k8s-tools")
logger = logging.getLogger("k8s-tools")
logging.basicConfig(level=logging.INFO)

def run_kubectl(args: List[str]) -> str:
    """Run a kubectl command and return the output."""
    try:
        cmd = ["kubectl"] + args
        logger.info(f"Running command: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        error_msg = f"Error running kubectl: {e.stderr}"
        logger.error(error_msg)
        return error_msg
    except Exception as e:
        return f"Unexpected error: {str(e)}"

@mcp.tool()
def k8s_get_resources(resource_type: str, namespace: Optional[str] = None, name: Optional[str] = None) -> str:
    """
    Get Kubernetes resources using kubectl.
    
    Args:
        resource_type: The type of resource to get (e.g., 'pods', 'deployments', 'services').
        namespace: The namespace to list resources from. If None, uses default or all namespaces if implied.
        name: The specific name of the resource to get.
    """
    args = ["get", resource_type]
    
    if namespace:
        args.extend(["-n", namespace])
    
    if name:
        args.append(name)
        
    # Output as YAML for better readability by LLM, or wide text
    args.extend(["-o", "yaml" if name else "wide"])
    
    return run_kubectl(args)

@mcp.tool()
def k8s_get_available_api_resources() -> str:
    """
    List the available API resources in the cluster.
    Equivalent to `kubectl api-resources`.
    """
    return run_kubectl(["api-resources"])

if __name__ == "__main__":
    # FastMCP handles the execution (stdio or sse/http depending on args)
    # But for our standalone server, we want to run it over HTTP/SSE
    # FastMCP 'run' defaults to stdio unless configured otherwise.
    # We will use the 'run' method which parses CLI args.
    # Usage: python k8s_mcp_server.py --transport sse --port 8084 --host 0.0.0.0
    mcp.run()
