"""
infra_validator.py — Validate full Azure infrastructure deployed by Terraform.

Checks:
  1. Resource Group exists
  2. VNet with correct subnets
  3. VM running
  4. Application Gateway operational
  5. Azure SQL available

Usage:
    python infra_validator.py --resource-group rg-full-infra
    python infra_validator.py --resource-group rg-full-infra --subscription-id <id>

Requirements:
    pip install azure-mgmt-network azure-mgmt-compute azure-mgmt-sql azure-identity
    pip install azure-mgmt-resource
"""

import argparse
import sys
from dataclasses import dataclass
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.sql import SqlManagementClient
from azure.core.exceptions import ResourceNotFoundError


@dataclass
class CheckResult:
    name: str
    passed: bool
    message: str
    details: list[str] = None


def ok(msg: str) -> None:
    print(f"  \033[92m✔\033[0m  {msg}")

def fail(msg: str) -> None:
    print(f"  \033[91m✘\033[0m  {msg}")

def info(msg: str) -> None:
    print(f"  \033[94mℹ\033[0m  {msg}")

def section(title: str) -> None:
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


# ─────────────────────────────────────────────
# Validators
# ─────────────────────────────────────────────

def validate_resource_group(
    resource_client: ResourceManagementClient,
    resource_group: str,
) -> CheckResult:
    section("1. Resource Group")
    try:
        rg = resource_client.resource_groups.get(resource_group)
        state = rg.properties.provisioning_state
        if state == "Succeeded":
            ok(f"Resource Group '{resource_group}' exists")
            ok(f"Location: {rg.location}")
            ok(f"State: {state}")
            return CheckResult("Resource Group", True, f"Exists in {rg.location}")
        else:
            fail(f"Resource Group state: {state}")
            return CheckResult("Resource Group", False, f"State: {state}")
    except ResourceNotFoundError:
        fail(f"Resource Group '{resource_group}' not found")
        return CheckResult("Resource Group", False, "Not found")


def validate_vnet(
    network_client: NetworkManagementClient,
    resource_group: str,
) -> CheckResult:
    section("2. Virtual Network + Subnets")
    vnets = list(network_client.virtual_networks.list(resource_group))
    if not vnets:
        fail("No VNets found")
        return CheckResult("VNet", False, "Not found")

    vnet = vnets[0]
    ok(f"VNet: {vnet.name}")
    ok(f"Address space: {', '.join(vnet.address_space.address_prefixes)}")

    subnets = list(network_client.subnets.list(resource_group, vnet.name))
    ok(f"Subnets: {len(subnets)}")

    expected_subnets = {"subnet-appgw", "subnet-web", "subnet-db"}
    found_subnets = {s.name for s in subnets}
    missing = expected_subnets - found_subnets

    for subnet in subnets:
        prefix = subnet.address_prefix or (subnet.address_prefixes[0] if subnet.address_prefixes else "?")
        nsg = subnet.network_security_group.id.split("/")[-1] if subnet.network_security_group else "None"
        ok(f"  {subnet.name}: {prefix} (NSG: {nsg})")

    if missing:
        fail(f"Missing expected subnets: {missing}")
        return CheckResult("VNet", False, f"Missing subnets: {missing}")

    return CheckResult("VNet", True, f"{len(subnets)} subnets configured")


def validate_vm(
    compute_client: ComputeManagementClient,
    resource_group: str,
) -> CheckResult:
    section("3. Virtual Machine")
    vms = list(compute_client.virtual_machines.list(resource_group))
    if not vms:
        fail("No VMs found")
        return CheckResult("VM", False, "Not found")

    all_running = True
    for vm in vms:
        vm_detail = compute_client.virtual_machines.get(
            resource_group, vm.name, expand="instanceView"
        )
        statuses = vm_detail.instance_view.statuses if vm_detail.instance_view else []
        power_state = next(
            (s.display_status for s in statuses if s.code and s.code.startswith("PowerState")),
            "Unknown"
        )
        provisioning = next(
            (s.display_status for s in statuses if s.code and s.code.startswith("ProvisioningState")),
            "Unknown"
        )

        if power_state == "VM running":
            ok(f"VM: {vm.name} — {power_state}")
        else:
            fail(f"VM: {vm.name} — {power_state}")
            all_running = False

        info(f"  Size: {vm.hardware_profile.vm_size}")
        info(f"  Provisioning: {provisioning}")

    return CheckResult("VM", all_running, f"{len(vms)} VM(s) checked")


def validate_application_gateway(
    network_client: NetworkManagementClient,
    resource_group: str,
) -> CheckResult:
    section("4. Application Gateway")
    gateways = list(network_client.application_gateways.list(resource_group))
    if not gateways:
        fail("No Application Gateways found")
        return CheckResult("App Gateway", False, "Not found")

    all_running = True
    for gw in gateways:
        state = gw.operational_state or "Unknown"
        provisioning = gw.provisioning_state or "Unknown"

        if state == "Running" and provisioning == "Succeeded":
            ok(f"App Gateway: {gw.name} — {state}")
        else:
            fail(f"App Gateway: {gw.name} — state={state}, provisioning={provisioning}")
            all_running = False

        info(f"  SKU: {gw.sku.name}")
        info(f"  Backend pools: {len(gw.backend_address_pools or [])}")

    return CheckResult("App Gateway", all_running, f"{len(gateways)} gateway(s) checked")


def validate_sql(
    sql_client: SqlManagementClient,
    resource_group: str,
) -> CheckResult:
    section("5. Azure SQL")
    servers = list(sql_client.servers.list_by_resource_group(resource_group))
    if not servers:
        fail("No Azure SQL servers found")
        return CheckResult("Azure SQL", False, "Not found")

    all_ok = True
    for server in servers:
        state = server.state or "Unknown"
        if state == "Ready":
            ok(f"SQL Server: {server.name} — {state}")
        else:
            fail(f"SQL Server: {server.name} — {state}")
            all_ok = False

        info(f"  FQDN: {server.fully_qualified_domain_name}")

        databases = list(sql_client.databases.list_by_server(resource_group, server.name))
        user_dbs = [db for db in databases if db.name != "master"]
        ok(f"  Databases: {len(user_dbs)}")

        for db in user_dbs:
            db_status = db.status or "Unknown"
            if db_status == "Online":
                ok(f"    {db.name}: {db_status}")
            else:
                fail(f"    {db.name}: {db_status}")
                all_ok = False

    return CheckResult("Azure SQL", all_ok, f"{len(servers)} server(s) checked")


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Azure infrastructure validator")
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--subscription-id")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║         Azure Infrastructure Validation Report           ║")
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

    resource_client = ResourceManagementClient(credential, subscription_id)
    network_client = NetworkManagementClient(credential, subscription_id)
    compute_client = ComputeManagementClient(credential, subscription_id)
    sql_client = SqlManagementClient(credential, subscription_id)

    results = [
        validate_resource_group(resource_client, args.resource_group),
        validate_vnet(network_client, args.resource_group),
        validate_vm(compute_client, args.resource_group),
        validate_application_gateway(network_client, args.resource_group),
        validate_sql(sql_client, args.resource_group),
    ]

    # Summary table
    section("Validation Summary")
    passed = sum(1 for r in results if r.passed)
    total = len(results)

    print(f"\n  {'Check':<25} {'Status':<10} {'Details'}")
    print(f"  {'─' * 60}")
    for r in results:
        status = "\033[92mPASS\033[0m" if r.passed else "\033[91mFAIL\033[0m"
        print(f"  {r.name:<25} {status:<18} {r.message}")

    print(f"\n{'═' * 60}")
    if passed == total:
        print(f"  \033[92m✔  All {total} checks passed\033[0m")
    else:
        print(f"  \033[91m✘  {total - passed}/{total} checks failed\033[0m")
    print(f"{'═' * 60}\n")

    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
