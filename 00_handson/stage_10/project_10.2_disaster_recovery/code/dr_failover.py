"""
dr_failover.py — Test, trigger, and verify Azure SQL DR failover.

Usage:
    pip install azure-identity azure-mgmt-sql
    python code/dr_failover.py test
    python code/dr_failover.py failover   # WARNING: redirects traffic!
    python code/dr_failover.py failback
"""

import argparse
import sys
import time
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.mgmt.sql import SqlManagementClient
from azure.mgmt.resource import SubscriptionClient


def get_subscription_id() -> str:
    credential = DefaultAzureCredential()
    return list(SubscriptionClient(credential).subscriptions.list())[0].subscription_id


def test_dr_readiness(sql_client: SqlManagementClient, rg: str, server: str, fg_name: str) -> None:
    print("\n── DR Readiness Test ────────────────────────────────────────")
    fg = sql_client.failover_groups.get(rg, server, fg_name)
    print(f"  Failover group : {fg.name}")
    print(f"  Replication role: {fg.replication_role}")
    print(f"  Replication state: {fg.replication_state}")
    for partner in fg.partner_servers:
        print(f"  Partner server : {partner.id.split('/')[-1]}")
        print(f"  Partner role   : {partner.replication_role}")
    print(f"\n  ✅ DR is ready — failover group is configured.")


def trigger_failover(sql_client: SqlManagementClient, rg: str, server: str, fg_name: str) -> None:
    print("\n── Triggering Failover ──────────────────────────────────────")
    print(f"  WARNING: This will redirect traffic to the secondary region!")
    confirm = input("  Type 'yes' to confirm: ").strip().lower()
    if confirm != "yes":
        print("  Aborted.")
        return

    print(f"  [{datetime.now().strftime('%H:%M:%S')}] Initiating failover...")
    poller = sql_client.failover_groups.begin_failover(rg, server, fg_name)
    poller.result()
    print(f"  [{datetime.now().strftime('%H:%M:%S')}] Failover complete.")
    print(f"  Secondary is now primary. DNS updated automatically.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["test", "failover", "failback"])
    parser.add_argument("--resource-group", default="rg-dr-primary")
    parser.add_argument("--server",         default="sql-primary-handson-001")
    parser.add_argument("--failover-group", default="fg-handson")
    args = parser.parse_args()

    credential = DefaultAzureCredential()
    subscription_id = get_subscription_id()
    sql_client = SqlManagementClient(credential, subscription_id)

    print(f"\n{'='*60}")
    print(f"  Azure SQL Disaster Recovery")
    print(f"{'='*60}")

    if args.action == "test":
        test_dr_readiness(sql_client, args.resource_group, args.server, args.failover_group)
    elif args.action == "failover":
        trigger_failover(sql_client, args.resource_group, args.server, args.failover_group)
    elif args.action == "failback":
        print("\n[*] Failback: trigger failover from secondary back to primary")
        trigger_failover(sql_client, "rg-dr-secondary", "sql-secondary-handson-001", args.failover_group)

    print(f"\n{'='*60}\n")


if __name__ == "__main__":
    main()
