"""
health_check.py — Check health of multi-tier Azure application.

Checks:
  1. Application Gateway operational state
  2. VMSS instance count and health
  3. Azure SQL availability

Usage:
    python health_check.py --resource-group rg-multitier
    python health_check.py --resource-group rg-multitier --subscription-id <id>

Requirements:
    pip install azure-mgmt-network azure-mgmt-compute azure-mgmt-sql azure-identity
"""

import argparse
import sys
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.sql import SqlManagementClient
from azure.core.exceptions import ResourceNotFoundError


# ─────────────────────────────────────────────
# Output helpers
# ─────────────────────────────────────────────

def ok(msg: str) -> None:
    print(f"  \033[92m✔\033[0m  {msg}")

def warn(msg: str) -> None:
    print(f"  \033[93m⚠\033[0m  {msg}")

def fail(msg: str) -> None:
    print(f"  \033[91m✘\033[0m  {msg}")

def info(msg: str) -> None:
    print(f"  \033[94mℹ\033[0m  {msg}")

def section(title: str) -> None:
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


# ─────────────────────────────────────────────
# Health checks
# ─────────────────────────────────────────────

def check_application_gateway(
    network_client: NetworkManagementClient,
    resource_group: str,
) -> tuple[bool, str]:
    section("1. Application Gateway")
    try:
        gateways = list(network_client.application_gateways.list(resource_group))
        if not gateways:
            fail("No Application Gateways found in resource group")
            return False, "not_found"

        all_healthy = True
        for gw in gateways:
            state = gw.operational_state or "Unknown"
            provisioning = gw.provisioning_state or "Unknown"

            if state == "Running" and provisioning == "Succeeded":
                ok(f"{gw.name}: state={state}, provisioning={provisioning}")
            else:
                fail(f"{gw.name}: state={state}, provisioning={provisioning}")
                all_healthy = False

            info(f"  SKU: {gw.sku.name} (capacity: {gw.sku.capacity})")
            info(f"  WAF enabled: {gw.web_application_firewall_configuration is not None}")

            # Backend pool info
            for pool in (gw.backend_address_pools or []):
                count = len(pool.backend_addresses or []) + len(pool.backend_ip_configurations or [])
                info(f"  Backend pool '{pool.name}': {count} target(s)")

        return all_healthy, "ok"

    except Exception as e:
        fail(f"Error checking Application Gateway: {e}")
        return False, str(e)


def check_vmss(
    compute_client: ComputeManagementClient,
    resource_group: str,
) -> tuple[bool, str]:
    section("2. VM Scale Sets")
    try:
        scale_sets = list(compute_client.virtual_machine_scale_sets.list(resource_group))
        if not scale_sets:
            fail("No VM Scale Sets found in resource group")
            return False, "not_found"

        all_healthy = True
        for vmss in scale_sets:
            provisioning = vmss.provisioning_state or "Unknown"

            if provisioning == "Succeeded":
                ok(f"{vmss.name}: provisioning={provisioning}")
            else:
                fail(f"{vmss.name}: provisioning={provisioning}")
                all_healthy = False

            info(f"  SKU: {vmss.sku.name} x{vmss.sku.capacity}")
            info(f"  Upgrade mode: {vmss.upgrade_policy.mode if vmss.upgrade_policy else 'Unknown'}")

            # List instances
            instances = list(compute_client.virtual_machine_scale_set_vms.list(
                resource_group, vmss.name
            ))
            ok(f"  Instance count: {len(instances)}")

            healthy = 0
            unhealthy = 0
            for inst in instances:
                inst_view = compute_client.virtual_machine_scale_set_vms.get_instance_view(
                    resource_group, vmss.name, inst.instance_id
                )
                # Check VM agent status
                vm_agent = inst_view.vm_agent
                if vm_agent and vm_agent.statuses:
                    for status in vm_agent.statuses:
                        if "ProvisioningState/succeeded" in (status.code or ""):
                            healthy += 1
                        elif "ProvisioningState/failed" in (status.code or ""):
                            unhealthy += 1

            if unhealthy > 0:
                warn(f"  Healthy: {healthy}, Unhealthy: {unhealthy}")
                all_healthy = False
            else:
                ok(f"  All {healthy} instance(s) healthy")

        return all_healthy, "ok"

    except Exception as e:
        fail(f"Error checking VMSS: {e}")
        return False, str(e)


def check_azure_sql(
    sql_client: SqlManagementClient,
    resource_group: str,
) -> tuple[bool, str]:
    section("3. Azure SQL")
    try:
        servers = list(sql_client.servers.list_by_resource_group(resource_group))
        if not servers:
            fail("No Azure SQL Servers found in resource group")
            return False, "not_found"

        all_healthy = True
        for server in servers:
            state = server.state or "Unknown"

            if state == "Ready":
                ok(f"Server: {server.name} — state={state}")
            else:
                fail(f"Server: {server.name} — state={state}")
                all_healthy = False

            info(f"  FQDN: {server.fully_qualified_domain_name}")
            info(f"  Version: {server.version}")

            # List databases
            databases = list(sql_client.databases.list_by_server(resource_group, server.name))
            ok(f"  Databases: {len(databases)}")
            for db in databases:
                if db.name == "master":
                    continue
                db_status = db.status or "Unknown"
                if db_status == "Online":
                    ok(f"    {db.name}: {db_status} (SKU: {db.sku.name if db.sku else 'N/A'})")
                else:
                    fail(f"    {db.name}: {db_status}")
                    all_healthy = False

        return all_healthy, "ok"

    except Exception as e:
        fail(f"Error checking Azure SQL: {e}")
        return False, str(e)


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Multi-tier Azure app health checker")
    parser.add_argument("--resource-group", required=True, help="Resource group name")
    parser.add_argument("--subscription-id", help="Azure subscription ID")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║         Multi-Tier Application Health Report             ║")
    print(f"║  {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC'):<54}║")
    print("╚══════════════════════════════════════════════════════════╝")

    credential = DefaultAzureCredential()

    if args.subscription_id:
        subscription_id = args.subscription_id
    else:
        from azure.mgmt.subscription import SubscriptionClient
        sub_client = SubscriptionClient(credential)
        subscriptions = list(sub_client.subscriptions.list())
        if not subscriptions:
            print("\nERROR: No subscriptions found. Run 'az login' first.")
            sys.exit(1)
        subscription_id = subscriptions[0].subscription_id
        info(f"Using subscription: {subscription_id}")

    network_client = NetworkManagementClient(credential, subscription_id)
    compute_client = ComputeManagementClient(credential, subscription_id)
    sql_client = SqlManagementClient(credential, subscription_id)

    results = {}
    results["appgw"], _ = check_application_gateway(network_client, args.resource_group)
    results["vmss"], _ = check_vmss(compute_client, args.resource_group)
    results["sql"], _ = check_azure_sql(sql_client, args.resource_group)

    # Summary
    section("Overall Health Summary")
    all_ok = True
    for component, healthy in results.items():
        if healthy:
            ok(f"{component.upper():<10} HEALTHY")
        else:
            fail(f"{component.upper():<10} UNHEALTHY")
            all_ok = False

    print(f"\n{'═' * 60}")
    if all_ok:
        print("  \033[92m✔  All systems healthy\033[0m")
    else:
        print("  \033[91m✘  One or more systems need attention\033[0m")
    print(f"{'═' * 60}\n")

    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
