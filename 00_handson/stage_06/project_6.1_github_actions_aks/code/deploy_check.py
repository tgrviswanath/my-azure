"""
Project 6.1 — GitHub Actions AKS: Post-Deployment Verification
===============================================================
Verifies that a deployment to AKS is healthy after a CI/CD pipeline run.
Checks:
  - Deployment exists and has the expected replica count
  - All pods are Running and Ready
  - Service has an external IP (LoadBalancer)
  - HTTP health check returns 200

Requirements:
    pip install azure-identity azure-mgmt-containerservice kubernetes requests

Environment variables:
    AKS_CLUSTER_NAME    — AKS cluster name
    AKS_RESOURCE_GROUP  — Resource group containing the AKS cluster
    DEPLOYMENT_NAME     — Kubernetes deployment name (default: myapp)
    NAMESPACE           — Kubernetes namespace (default: default)
    EXPECTED_REPLICAS   — Expected number of running pods (default: 2)
"""

import os
import sys
import time
import logging
import requests

from azure.identity import DefaultAzureCredential
from azure.mgmt.containerservice import ContainerServiceClient

# kubernetes client — install with: pip install kubernetes
try:
    from kubernetes import client as k8s_client, config as k8s_config
    K8S_AVAILABLE = True
except ImportError:
    K8S_AVAILABLE = False
    logging.warning("kubernetes package not installed. Run: pip install kubernetes")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


# ── Configuration ──────────────────────────────────────────────────────────────

CLUSTER_NAME      = os.environ.get("AKS_CLUSTER_NAME", "")
RESOURCE_GROUP    = os.environ.get("AKS_RESOURCE_GROUP", "")
DEPLOYMENT_NAME   = os.environ.get("DEPLOYMENT_NAME", "myapp")
NAMESPACE         = os.environ.get("NAMESPACE", "default")
EXPECTED_REPLICAS = int(os.environ.get("EXPECTED_REPLICAS", "2"))
SUBSCRIPTION_ID   = os.environ.get("AZURE_SUBSCRIPTION_ID", "")


# ── AKS Credential Fetch ───────────────────────────────────────────────────────

def get_aks_credentials() -> str:
    """
    Fetch the kubeconfig for the AKS cluster using the Azure SDK.
    Returns the kubeconfig as a string.
    """
    if not CLUSTER_NAME or not RESOURCE_GROUP:
        raise EnvironmentError(
            "AKS_CLUSTER_NAME and AKS_RESOURCE_GROUP must be set."
        )

    credential = DefaultAzureCredential()

    # Resolve subscription ID if not set
    sub_id = SUBSCRIPTION_ID
    if not sub_id:
        from azure.mgmt.resource import SubscriptionClient
        sub_client = SubscriptionClient(credential)
        sub_id = next(sub_client.subscriptions.list()).subscription_id
        log.info("Using subscription: %s", sub_id)

    aks_client = ContainerServiceClient(credential, sub_id)

    log.info("Fetching kubeconfig for cluster %s in %s...", CLUSTER_NAME, RESOURCE_GROUP)
    creds = aks_client.managed_clusters.list_cluster_user_credentials(
        RESOURCE_GROUP, CLUSTER_NAME
    )

    # The kubeconfig is base64-encoded in the response
    import base64
    kubeconfig_bytes = creds.kubeconfigs[0].value
    return kubeconfig_bytes.decode("utf-8")


# ── Kubernetes Checks ──────────────────────────────────────────────────────────

def load_kube_config_from_string(kubeconfig_str: str) -> None:
    """Load kubeconfig from a string into the kubernetes client."""
    import tempfile
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
        f.write(kubeconfig_str)
        tmp_path = f.name
    k8s_config.load_kube_config(config_file=tmp_path)
    os.unlink(tmp_path)


def check_deployment(apps_v1: k8s_client.AppsV1Api) -> dict:
    """Check that the deployment exists and has the expected replica count."""
    log.info("Checking deployment: %s/%s", NAMESPACE, DEPLOYMENT_NAME)

    try:
        deployment = apps_v1.read_namespaced_deployment(DEPLOYMENT_NAME, NAMESPACE)
    except k8s_client.exceptions.ApiException as e:
        if e.status == 404:
            return {"status": "FAIL", "reason": f"Deployment '{DEPLOYMENT_NAME}' not found in namespace '{NAMESPACE}'"}
        raise

    spec_replicas    = deployment.spec.replicas or 0
    ready_replicas   = deployment.status.ready_replicas or 0
    updated_replicas = deployment.status.updated_replicas or 0
    image            = deployment.spec.template.spec.containers[0].image

    log.info("  Spec replicas   : %d", spec_replicas)
    log.info("  Ready replicas  : %d", ready_replicas)
    log.info("  Updated replicas: %d", updated_replicas)
    log.info("  Current image   : %s", image)

    if ready_replicas < EXPECTED_REPLICAS:
        return {
            "status": "FAIL",
            "reason": f"Only {ready_replicas}/{EXPECTED_REPLICAS} replicas ready",
            "image": image,
        }

    return {
        "status": "PASS",
        "ready_replicas": ready_replicas,
        "image": image,
    }


def check_pods(core_v1: k8s_client.CoreV1Api) -> dict:
    """Check that all pods for the deployment are Running and Ready."""
    log.info("Checking pods for deployment: %s", DEPLOYMENT_NAME)

    pods = core_v1.list_namespaced_pod(
        NAMESPACE,
        label_selector=f"app={DEPLOYMENT_NAME}"
    )

    if not pods.items:
        return {"status": "FAIL", "reason": "No pods found matching label selector"}

    results = []
    all_ready = True

    for pod in pods.items:
        pod_name  = pod.metadata.name
        phase     = pod.status.phase
        ready     = all(
            cs.ready for cs in (pod.status.container_statuses or [])
        )
        restarts  = sum(
            cs.restart_count for cs in (pod.status.container_statuses or [])
        )

        log.info("  Pod: %-50s  Phase: %-10s  Ready: %s  Restarts: %d",
                 pod_name, phase, ready, restarts)

        if phase != "Running" or not ready:
            all_ready = False

        results.append({
            "name": pod_name,
            "phase": phase,
            "ready": ready,
            "restarts": restarts,
        })

    return {
        "status": "PASS" if all_ready else "FAIL",
        "pods": results,
        "total": len(results),
    }


def check_service(core_v1: k8s_client.CoreV1Api, timeout_seconds: int = 120) -> dict:
    """
    Check that the LoadBalancer service has an external IP.
    Waits up to timeout_seconds for the IP to be assigned.
    """
    service_name = f"{DEPLOYMENT_NAME}-service"
    log.info("Checking service: %s/%s", NAMESPACE, service_name)

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            svc = core_v1.read_namespaced_service(service_name, NAMESPACE)
        except k8s_client.exceptions.ApiException as e:
            if e.status == 404:
                return {"status": "FAIL", "reason": f"Service '{service_name}' not found"}
            raise

        ingress = svc.status.load_balancer.ingress
        if ingress and ingress[0].ip:
            external_ip = ingress[0].ip
            port = svc.spec.ports[0].port
            log.info("  External IP: %s  Port: %d", external_ip, port)
            return {
                "status": "PASS",
                "external_ip": external_ip,
                "port": port,
                "url": f"http://{external_ip}:{port}",
            }

        log.info("  Waiting for external IP... (%ds remaining)", int(deadline - time.time()))
        time.sleep(10)

    return {"status": "FAIL", "reason": "Timed out waiting for external IP"}


def check_http_health(url: str, expected_status: int = 200) -> dict:
    """Perform an HTTP GET health check against the service URL."""
    health_url = f"{url}/health" if not url.endswith("/") else f"{url}health"
    log.info("HTTP health check: GET %s", health_url)

    try:
        response = requests.get(url, timeout=10)
        log.info("  HTTP %d  Body: %s", response.status_code, response.text[:100])

        if response.status_code == expected_status:
            return {"status": "PASS", "http_status": response.status_code, "body": response.text[:200]}
        else:
            return {"status": "FAIL", "http_status": response.status_code, "body": response.text[:200]}

    except requests.exceptions.ConnectionError as e:
        return {"status": "FAIL", "reason": f"Connection error: {e}"}
    except requests.exceptions.Timeout:
        return {"status": "FAIL", "reason": "Request timed out after 10s"}


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    if not K8S_AVAILABLE:
        log.error("kubernetes package required. Run: pip install kubernetes")
        sys.exit(1)

    log.info("=" * 60)
    log.info("AKS Deployment Verification")
    log.info("Cluster   : %s", CLUSTER_NAME)
    log.info("Namespace : %s", NAMESPACE)
    log.info("Deployment: %s", DEPLOYMENT_NAME)
    log.info("=" * 60)

    # Load kubeconfig
    try:
        kubeconfig = get_aks_credentials()
        load_kube_config_from_string(kubeconfig)
    except Exception as e:
        log.error("Failed to load kubeconfig: %s", e)
        log.info("Falling back to local kubeconfig (~/.kube/config)")
        k8s_config.load_kube_config()

    apps_v1 = k8s_client.AppsV1Api()
    core_v1 = k8s_client.CoreV1Api()

    results = {}

    # Run checks
    results["deployment"] = check_deployment(apps_v1)
    results["pods"]       = check_pods(core_v1)
    results["service"]    = check_service(core_v1)

    if results["service"]["status"] == "PASS":
        results["http"] = check_http_health(results["service"]["url"])
    else:
        results["http"] = {"status": "SKIP", "reason": "No external IP available"}

    # Summary
    log.info("\n" + "=" * 60)
    log.info("VERIFICATION SUMMARY")
    log.info("=" * 60)

    all_passed = True
    for check_name, result in results.items():
        status = result.get("status", "UNKNOWN")
        icon   = "✓" if status == "PASS" else ("⚠" if status == "SKIP" else "✗")
        log.info("  %s  %-15s  %s", icon, check_name.upper(), status)
        if status not in ("PASS", "SKIP"):
            all_passed = False
            log.info("      Reason: %s", result.get("reason", "see above"))

    log.info("=" * 60)

    if all_passed:
        log.info("All checks PASSED. Deployment is healthy.")
        sys.exit(0)
    else:
        log.error("One or more checks FAILED. Review the output above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
