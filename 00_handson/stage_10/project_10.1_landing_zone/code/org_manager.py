"""
org_manager.py — List Azure Management Groups, policy assignments, and compliance.

Usage:
    pip install azure-identity azure-mgmt-managementgroups azure-mgmt-resource
    python code/org_manager.py [list-mgs|list-policies|check-compliance]
"""

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.managementgroups import ManagementGroupsAPI
from azure.mgmt.resource import SubscriptionClient


def list_management_groups(client: ManagementGroupsAPI) -> None:
    print("\n── Management Groups ────────────────────────────────────────")
    print(f"  {'Name':<30} {'Display Name':<30} {'Type'}")
    print(f"  {'-'*30} {'-'*30} {'-'*20}")
    for mg in client.management_groups.list():
        print(f"  {mg.name:<30} {mg.display_name:<30} {mg.type}")


def list_subscriptions(sub_client: SubscriptionClient) -> None:
    print("\n── Subscriptions ────────────────────────────────────────────")
    print(f"  {'Name':<35} {'ID':<40} {'State'}")
    print(f"  {'-'*35} {'-'*40} {'-'*10}")
    for sub in sub_client.subscriptions.list():
        print(f"  {sub.display_name:<35} {sub.subscription_id:<40} {sub.state}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", nargs="?", default="all",
                        choices=["list-mgs", "list-subs", "all"])
    args = parser.parse_args()

    credential = DefaultAzureCredential()
    mg_client  = ManagementGroupsAPI(credential)
    sub_client = SubscriptionClient(credential)

    print(f"\n{'='*65}")
    print(f"  Azure Organization Manager")
    print(f"{'='*65}")

    if args.action in ("list-mgs", "all"):
        list_management_groups(mg_client)
    if args.action in ("list-subs", "all"):
        list_subscriptions(sub_client)

    print(f"\n{'='*65}\n")


if __name__ == "__main__":
    main()
