"""
aks_deploy.py — Deploy and verify workloads on Azure Kubernetes Service.

Usage:
    pip install azure-identity azure-mgmt-containerservice kubernetes
    az aks get-credentials --resource-group rg-aks --name aks-handson

    python code/aks_deploy.py deploy  --image acrhandson001.azurecr.io/myapp:v2.0
    python code/aks_deploy.py status
    python code/aks_deploy.py rollout --image acrhandson001.azurecr.io/myapp:v1.0
"""

import argparse
import subprocess
import sys
import json
import time
from azure.identity import DefaultAzureCredential
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.resource import SubscriptionClient


def get_subscription_id() -> str:
    credential = DefaultAzureCredential()
    return list(SubscriptionClient(credential).subscriptions.list())[0].subscription_id


def run_kubectl(args: list[str], capture: bool = False) -> tuple[int, str]:
    """Run a kubectl command."""
    cmd = ["kubectl"] + args
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout
    else:
        print(f"  $ kubectl {' '.join(args)}")
        result = subprocess.run(cmd)
        return result.returncode, ""


def cmd_deploy(image: str, namespace: str, deployment: str) -> int:
    """Update deployment image and wait for rollout."""
    print(f"\n{'='*60}")
    print(f"  AKS Deployment")
    print(f"{'='*60}")
    print(f"  Namespace  : {namespace}")
    print(f"  Deployment : {deployment}")
    print(f"  Image      : {image}\n")

    # Update image
    rc, _ = run_kubectl([
        "set", "image",
        f"deployment/{deployment}",
        f"{deployment}={image}",
        "-n", namespace
    ])
    if rc != 0:
        print(f"[ERR] Failed to update image.")
        return rc

    # Wait for rollout
    print(f"\n[*] Waiting for rollout to complete...")
    rc, _ = run_kubectl([
        "rollout", "status",
        f"deployment/{deployment}",
        "-n", namespace,
        "--timeout=300s"
    ])

    if rc == 0:
        print(f"\n[+] Deployment succeeded!")
        cmd_status(namespace)
    else:
        print(f"\n[ERR] Rollout failed. Check pod logs:")
        run_kubectl(["get", "pods", "-n", namespace])
        run_kubectl(["describe", "deployment", deployment, "-n", namespace])

    return rc


def cmd_status(namespace: str) -> int:
    """Show current deployment status."""
    print(f"\n{'='*60}")
    print(f"  AKS Deployment Status — namespace: {namespace}")
    print(f"{'='*60}\n")

    run_kubectl(["get", "pods", "-n", namespace, "-o", "wide"])
    print()
    run_kubectl(["get", "deployments", "-n", namespace])
    print()
    run_kubectl(["get", "services", "-n", namespace])
    print()
    run_kubectl(["get", "hpa", "-n", namespace])
    return 0


def cmd_rollout(image: str, namespace: str, deployment: str) -> int:
    """Rollback to a previous image version."""
    print(f"\n[*] Rolling back {deployment} to image: {image}")
    return cmd_deploy(image, namespace, deployment)


def main():
    parser = argparse.ArgumentParser(description="AKS deployment manager")
    parser.add_argument("--namespace",  default="handson", help="Kubernetes namespace")
    parser.add_argument("--deployment", default="handson-api", help="Deployment name")

    sub = parser.add_subparsers(dest="command", required=True)

    p_deploy = sub.add_parser("deploy", help="Deploy new image")
    p_deploy.add_argument("--image", required=True, help="Full image URI with tag")

    sub.add_parser("status", help="Show deployment status")

    p_rollout = sub.add_parser("rollout", help="Rollback to previous image")
    p_rollout.add_argument("--image", required=True, help="Image URI to rollback to")

    args = parser.parse_args()

    if args.command == "deploy":
        rc = cmd_deploy(args.image, args.namespace, args.deployment)
    elif args.command == "status":
        rc = cmd_status(args.namespace)
    elif args.command == "rollout":
        rc = cmd_rollout(args.image, args.namespace, args.deployment)
    else:
        rc = 1

    sys.exit(rc)


if __name__ == "__main__":
    main()
