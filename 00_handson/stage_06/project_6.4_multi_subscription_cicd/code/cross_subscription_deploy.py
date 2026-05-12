"""
cross_subscription_deploy.py — Deploy to a target Azure subscription.

Usage:
    pip install azure-identity azure-mgmt-resource
    python code/cross_subscription_deploy.py --subscription-id <id> --resource-group rg-app
"""

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient


def deploy_to_subscription(subscription_id: str, resource_group: str, location: str) -> None:
    print(f"\n{'='*60}")
    print(f"  Cross-Subscription Deploy")
    print(f"{'='*60}")
    print(f"  Subscription : {subscription_id}")
    print(f"  Resource Group: {resource_group}")

    credential = DefaultAzureCredential()
    client = ResourceManagementClient(credential, subscription_id)

    # Verify subscription access
    rgs = list(client.resource_groups.list())
    print(f"[+] Connected — {len(rgs)} resource groups in subscription")

    # Create/verify resource group
    rg = client.resource_groups.create_or_update(
        resource_group,
        {"location": location, "tags": {"ManagedBy": "github-actions", "Pipeline": "multi-subscription"}}
    )
    print(f"[+] Resource group '{rg.name}' ready (location: {rg.location})")

    # List resources in the group
    resources = list(client.resources.list_by_resource_group(resource_group))
    print(f"[+] Resources in group: {len(resources)}")
    for r in resources[:5]:
        print(f"    - {r.name} ({r.type})")

    print(f"\n[+] Deployment to subscription {subscription_id} verified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--resource-group",  required=True)
    parser.add_argument("--location",        default="eastus")
    args = parser.parse_args()
    deploy_to_subscription(args.subscription_id, args.resource_group, args.location)
