"""
container_apps_deploy.py — Deploy and manage Azure Container Apps.

Usage:
    pip install azure-identity azure-mgmt-appcontainers
    python code/container_apps_deploy.py deploy  --app ca-myapp --image acrhandson001.azurecr.io/myapp:v2.0
    python code/container_apps_deploy.py status  --app ca-myapp
    python code/container_apps_deploy.py scale   --app ca-myapp --min 0 --max 10
    python code/container_apps_deploy.py url     --app ca-myapp
"""

import argparse
import sys
import time
from azure.identity import DefaultAzureCredential
from azure.mgmt.appcontainers import ContainerAppsAPIClient
from azure.mgmt.resource import SubscriptionClient


def get_subscription_id() -> str:
    credential = DefaultAzureCredential()
    return list(SubscriptionClient(credential).subscriptions.list())[0].subscription_id


def get_client(subscription_id: str) -> ContainerAppsAPIClient:
    return ContainerAppsAPIClient(DefaultAzureCredential(), subscription_id)


def cmd_deploy(client: ContainerAppsAPIClient, rg: str, app_name: str, image: str) -> int:
    """Update Container App with new image."""
    print(f"\n{'='*60}")
    print(f"  Container Apps Deploy")
    print(f"{'='*60}")
    print(f"  App   : {app_name}")
    print(f"  Image : {image}\n")

    # Get current app config
    app = client.container_apps.get(rg, app_name)
    template = app.template

    # Update image in first container
    if template.containers:
        old_image = template.containers[0].image
        template.containers[0].image = image
        print(f"[*] Updating image: {old_image} → {image}")

    # Update the app
    poller = client.container_apps.begin_update(rg, app_name, {"template": template})
    result = poller.result()

    print(f"[+] Deployment triggered. New revision: {result.latest_revision_name}")
    print(f"[*] Waiting for revision to be active...")

    # Poll for active revision
    for _ in range(30):
        app = client.container_apps.get(rg, app_name)
        if app.latest_ready_revision_name == result.latest_revision_name:
            print(f"[+] Revision active: {app.latest_ready_revision_name}")
            print(f"[+] URL: https://{app.ingress.fqdn}")
            return 0
        time.sleep(10)

    print("[WARN] Timed out waiting for revision. Check Azure Portal.")
    return 1


def cmd_status(client: ContainerAppsAPIClient, rg: str, app_name: str) -> int:
    """Show Container App status."""
    app = client.container_apps.get(rg, app_name)

    print(f"\n{'='*60}")
    print(f"  Container App Status: {app_name}")
    print(f"{'='*60}")
    print(f"  Provisioning State : {app.provisioning_state}")
    print(f"  Latest Revision    : {app.latest_revision_name}")
    print(f"  Ready Revision     : {app.latest_ready_revision_name}")
    if app.ingress:
        print(f"  URL                : https://{app.ingress.fqdn}")
    if app.template and app.template.containers:
        print(f"  Image              : {app.template.containers[0].image}")
        print(f"  CPU                : {app.template.containers[0].resources.cpu}")
        print(f"  Memory             : {app.template.containers[0].resources.memory}")
    if app.template:
        print(f"  Min replicas       : {app.template.scale.min_replicas}")
        print(f"  Max replicas       : {app.template.scale.max_replicas}")
    return 0


def cmd_url(client: ContainerAppsAPIClient, rg: str, app_name: str) -> int:
    """Print the Container App URL."""
    app = client.container_apps.get(rg, app_name)
    if app.ingress:
        print(f"https://{app.ingress.fqdn}")
    else:
        print("[WARN] No ingress configured.")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Azure Container Apps manager")
    parser.add_argument("--resource-group", default="rg-container-apps")
    parser.add_argument("--app",            required=True, help="Container App name")

    sub = parser.add_subparsers(dest="command", required=True)

    p_deploy = sub.add_parser("deploy", help="Deploy new image")
    p_deploy.add_argument("--image", required=True)

    sub.add_parser("status", help="Show app status")
    sub.add_parser("url",    help="Print app URL")

    args = parser.parse_args()

    subscription_id = get_subscription_id()
    client = get_client(subscription_id)

    if args.command == "deploy":
        rc = cmd_deploy(client, args.resource_group, args.app, args.image)
    elif args.command == "status":
        rc = cmd_status(client, args.resource_group, args.app)
    elif args.command == "url":
        rc = cmd_url(client, args.resource_group, args.app)
    else:
        rc = 1

    sys.exit(rc)


if __name__ == "__main__":
    main()
