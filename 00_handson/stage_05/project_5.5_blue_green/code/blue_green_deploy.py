"""
blue_green_deploy.py — Blue-green deployment controller for AKS.

Usage:
    pip install kubernetes
    az aks get-credentials --resource-group rg-aks --name aks-handson

    python code/blue_green_deploy.py deploy-green --image acrhandson001.azurecr.io/myapp:v2.0
    python code/blue_green_deploy.py switch-to-green
    python code/blue_green_deploy.py rollback
    python code/blue_green_deploy.py status
"""

import argparse
import subprocess
import sys
import json
import time


def run_kubectl(args: list[str], capture: bool = False) -> tuple[int, str]:
    cmd = ["kubectl"] + args
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout
    print(f"  $ kubectl {' '.join(args)}")
    return subprocess.run(cmd).returncode, ""


def get_current_active() -> str:
    """Return 'blue' or 'green' based on current service selector."""
    rc, output = run_kubectl([
        "get", "service", "myapp-svc",
        "-n", "handson",
        "-o", "jsonpath={.spec.selector.version}",
    ], capture=True)
    return output.strip() if rc == 0 else "unknown"


def cmd_deploy_green(image: str, namespace: str) -> int:
    """Deploy green (new) version alongside blue."""
    print(f"\n{'='*60}")
    print(f"  Blue-Green: Deploy Green (v2)")
    print(f"{'='*60}")
    print(f"  Image: {image}\n")

    green_manifest = f"""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
  namespace: {namespace}
  labels:
    app: myapp
    version: green
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
      - name: myapp
        image: {image}
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
"""
    # Apply green deployment
    result = subprocess.run(
        ["kubectl", "apply", "-f", "-"],
        input=green_manifest, text=True
    )
    if result.returncode != 0:
        print("[ERR] Failed to deploy green.")
        return result.returncode

    # Wait for green to be ready
    print("\n[*] Waiting for green deployment to be ready...")
    rc, _ = run_kubectl([
        "rollout", "status", "deployment/myapp-green",
        "-n", namespace, "--timeout=120s"
    ])

    if rc == 0:
        print("\n[+] Green deployment is ready.")
        print("[*] Run 'switch-to-green' to shift traffic, or 'rollback' to remove green.")
        cmd_status(namespace)
    else:
        print("[ERR] Green deployment failed readiness check.")

    return rc


def cmd_switch_to_green(namespace: str) -> int:
    """Switch service selector to green — instant traffic shift."""
    current = get_current_active()
    print(f"\n[*] Switching traffic: {current} → green")

    rc, _ = run_kubectl([
        "patch", "service", "myapp-svc",
        "-n", namespace,
        "-p", '{"spec":{"selector":{"version":"green"}}}'
    ])

    if rc == 0:
        print("[+] Traffic switched to green (v2).")
        print("[*] Blue deployment still running — run 'cleanup-blue' when verified.")
    else:
        print("[ERR] Failed to switch traffic.")

    return rc


def cmd_rollback(namespace: str) -> int:
    """Rollback: switch traffic back to blue."""
    current = get_current_active()
    print(f"\n[*] Rolling back: {current} → blue")

    rc, _ = run_kubectl([
        "patch", "service", "myapp-svc",
        "-n", namespace,
        "-p", '{"spec":{"selector":{"version":"blue"}}}'
    ])

    if rc == 0:
        print("[+] Traffic rolled back to blue (v1).")
        # Clean up failed green deployment
        run_kubectl(["delete", "deployment", "myapp-green", "-n", namespace])
        print("[+] Green deployment removed.")
    else:
        print("[ERR] Rollback failed.")

    return rc


def cmd_status(namespace: str) -> int:
    """Show blue/green deployment status."""
    print(f"\n  Active version: {get_current_active()}")
    run_kubectl(["get", "deployments", "-n", namespace, "-l", "app=myapp"])
    print()
    run_kubectl(["get", "pods", "-n", namespace, "-l", "app=myapp"])
    return 0


def main():
    parser = argparse.ArgumentParser(description="Blue-green deployment for AKS")
    parser.add_argument("--namespace", default="handson")

    sub = parser.add_subparsers(dest="command", required=True)

    p_green = sub.add_parser("deploy-green", help="Deploy green (new) version")
    p_green.add_argument("--image", required=True)

    sub.add_parser("switch-to-green", help="Switch traffic to green")
    sub.add_parser("rollback",        help="Rollback traffic to blue")
    sub.add_parser("status",          help="Show blue/green status")

    args = parser.parse_args()

    if args.command == "deploy-green":
        rc = cmd_deploy_green(args.image, args.namespace)
    elif args.command == "switch-to-green":
        rc = cmd_switch_to_green(args.namespace)
    elif args.command == "rollback":
        rc = cmd_rollback(args.namespace)
    elif args.command == "status":
        rc = cmd_status(args.namespace)
    else:
        rc = 1

    sys.exit(rc)


if __name__ == "__main__":
    main()
