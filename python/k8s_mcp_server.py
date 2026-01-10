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
def echo_test(message: str) -> str:
    """A simple echo tool to verify server connectivity."""
    return f"Echo from Kagent Tools: {message}"

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

# Define a middleware to fix the Host header for FastMCP
class HostHeaderMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            new_headers = []
            for name, value in scope["headers"]:
                if name == b"host":
                    # FastMCP validates Host header and rejects k8s service names (421 Misdirected Request)
                    # We rewrite it to localhost:8084 which it trusts.
                    new_headers.append((b"host", b"localhost:8084"))
                else:
                    new_headers.append((name, value))
            scope["headers"] = new_headers
        await self.app(scope, receive, send)

if __name__ == "__main__":
    import argparse
    import uvicorn
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--transport", default="stdio", choices=["stdio", "sse", "http"])
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--host", default="0.0.0.0")
    args, _ = parser.parse_known_args()

    if args.transport == "sse":
        logger.info(f"Starting MCP server on {args.host}:{args.port} (SSE)")
        # Use uvicorn to serve the SSE app directly, forcing HTTP/1.1 to avoid 421 errors
        # Wrap with middleware to fix Host header validation
        # NOTE: mcp.sse_app is a factory method, we must call it to get the ASGI app
        app = HostHeaderMiddleware(mcp.sse_app())
        uvicorn.run(app, host=args.host, port=args.port, http="h11")
    elif args.transport == "http":
        logger.info(f"Starting MCP server on {args.host}:{args.port} (Streamable HTTP)")
        # Use uvicorn to serve the Streamable HTTP app directly, forcing HTTP/1.1
        # Enable trace logging and allow all forwarded IPs to debug connection issues
        # Wrap with middleware to fix Host header validation
        # NOTE: mcp.streamable_http_app is a factory method, we must call it to get the ASGI app
        app = HostHeaderMiddleware(mcp.streamable_http_app())
        uvicorn.run(
            app, 
            host=args.host, 
            port=args.port, 
            http="h11", 
            log_level="trace",
            forwarded_allow_ips="*"
        )
    else:
        logger.info("Starting MCP server (STDIO)")
        mcp.run()
