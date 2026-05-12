"""
platform_health.py — Check health of all services in the microservices platform.

Usage:
    pip install azure-identity azure-mgmt-containerservice azure-mgmt-sql azure-mgmt-redis azure-mgmt-eventhub
    python code/platform_health.py
"""

import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.sql import SqlManagementClient
from azure.mgmt.redis import RedisManagementClient
from azure.mgmt.eventhub import EventHubManagementClient
from azure.mgmt.resource import SubscriptionClient

PASS = "\033[92m[PASS]\033[0m"
FAIL = "\033[91m[FAIL]\033[0m"
WARN = "\033[93m[WARN]\033[0m"
BOLD = "\033[1m"
RESET = "\033[0m"

RG = "rg-platform"


def get_subscription_id() -> str:
    credential = DefaultAzureCredential()
    return list(SubscriptionClient(credential).subscriptions.list())[0].subscription_id


def check_aks(client: ContainerServiceClient, rg: str) -> bool:
    print("\n── AKS Clusters ─────────────────────────────────────────────")
    all_ok = True
    for cluster in client.managed_clusters.list_by_resource_group(rg):
        state = cluster.provisioning_state
        ok = state == "Succeeded"
        icon = PASS if ok else FAIL
        print(f"  {icon} {cluster.name:<30} {state}")
        if not ok:
            all_ok = False
    return all_ok


def check_sql(client: SqlManagementClient, rg: str) -> bool:
    print("\n── Azure SQL Databases ──────────────────────────────────────")
    all_ok = True
    for server in client.servers.list_by_resource_group(rg):
        for db in client.databases.list_by_server(rg, server.name):
            if db.name == "master":
                continue
            state = db.status
            ok = state == "Online"
            icon = PASS if ok else FAIL
            print(f"  {icon} {server.name}/{db.name:<25} {state}")
            if not ok:
                all_ok = False
    return all_ok


def check_redis(client: RedisManagementClient, rg: str) -> bool:
    print("\n── Azure Cache for Redis ────────────────────────────────────")
    all_ok = True
    for cache in client.redis.list_by_resource_group(rg):
        state = cache.provisioning_state
        ok = state == "Succeeded"
        icon = PASS if ok else FAIL
        print(f"  {icon} {cache.name:<30} {state}")
        if not ok:
            all_ok = False
    return all_ok


def check_event_hubs(client: EventHubManagementClient, rg: str) -> bool:
    print("\n── Event Hubs ───────────────────────────────────────────────")
    all_ok = True
    for ns in client.namespaces.list_by_resource_group(rg):
        state = ns.provisioning_state
        ok = state == "Succeeded"
        icon = PASS if ok else FAIL
        print(f"  {icon} {ns.name:<30} {state}")
        if not ok:
            all_ok = False
    return all_ok


def main():
    credential = DefaultAzureCredential()
    subscription_id = get_subscription_id()

    aks_client = ContainerServiceClient(credential, subscription_id)
    sql_client = SqlManagementClient(credential, subscription_id)
    redis_client = RedisManagementClient(credential, subscription_id)
    evh_client = EventHubManagementClient(credential, subscription_id)

    print(f"\n{BOLD}{'='*60}{RESET}")
    print(f"{BOLD}  Platform Health Dashboard{RESET}")
    print(f"{BOLD}{'='*60}{RESET}")

    results = [
        check_aks(aks_client, RG),
        check_sql(sql_client, RG),
        check_redis(redis_client, RG),
        check_event_hubs(evh_client, RG),
    ]

    all_healthy = all(results)
    print(f"\n{'='*60}")
    if all_healthy:
        print(f"  {PASS} {BOLD}ALL SYSTEMS HEALTHY{RESET}")
    else:
        print(f"  {FAIL} {BOLD}PLATFORM DEGRADED — check failures above{RESET}")
    print(f"{'='*60}\n")

    sys.exit(0 if all_healthy else 1)


if __name__ == "__main__":
    main()
