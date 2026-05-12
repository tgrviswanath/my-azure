"""
vnet_checker.py — Verify Azure VNet configuration using azure-mgmt-network.

Usage:
    python vnet_checker.py --resource-group rg-vnet-lab --vnet-name vnet-main

Requirements:
    pip install azure-mgmt-network azure-identity
"""

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.network import NetworkManagementClient
from azure.core.exceptions import ResourceNotFoundError


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

def ok(msg: str) -> None:
    print(f"  \033[92m✔\033[0m  {msg}")

def fail(msg: str) -> None:
    print(f"  \033[91m✘\033[0m  {msg}")

def info(msg: str) -> None:
    print(f"  \033[94mℹ\033[0m  {msg}")

def section(title: str) -> None:
    print(f"\n{'─' * 55}")
    print(f"  {title}")
    print(f"{'─' * 55}")


# ─────────────────────────────────────────────
# Checks
# ─────────────────────────────────────────────

def check_vnet(client: NetworkManagementClient, rg: str, vnet_name: str) -> dict | None:
    section("1. Virtual Network")
    try:
        vnet = client.virtual_networks.get(rg, vnet_name)
        ok(f"VNet found: {vnet.name}")
        ok(f"Location: {vnet.location}")
        ok(f"Address space: {', '.join(vnet.address_space.address_prefixes)}")
        ok(f"Provisioning state: {vnet.provisioning_state}")
        return vnet
    except ResourceNotFoundError:
        fail(f"VNet '{vnet_name}' not found in resource group '{rg}'")
        return None


def check_subnets(client: NetworkManagementClient, rg: str, vnet_name: str) -> None:
    section("2. Subnets")
    subnets = list(client.subnets.list(rg, vnet_name))
    if not subnets:
        fail("No subnets found")
        return

    ok(f"Found {len(subnets)} subnet(s)")
    for subnet in subnets:
        prefix = subnet.address_prefix or (
            subnet.address_prefixes[0] if subnet.address_prefixes else "unknown"
        )
        nsg_name = subnet.network_security_group.id.split("/")[-1] if subnet.network_security_group else "None"
        nat_gw = subnet.nat_gateway.id.split("/")[-1] if subnet.nat_gateway else "None"
        rt = subnet.route_table.id.split("/")[-1] if subnet.route_table else "None"

        print(f"\n    Subnet: \033[1m{subnet.name}\033[0m")
        info(f"Address prefix : {prefix}")
        info(f"NSG            : {nsg_name}")
        info(f"NAT Gateway    : {nat_gw}")
        info(f"Route Table    : {rt}")
        info(f"State          : {subnet.provisioning_state}")


def check_nsgs(client: NetworkManagementClient, rg: str) -> None:
    section("3. Network Security Groups")
    nsgs = list(client.network_security_groups.list(rg))
    if not nsgs:
        fail("No NSGs found in resource group")
        return

    ok(f"Found {len(nsgs)} NSG(s)")
    for nsg in nsgs:
        print(f"\n    NSG: \033[1m{nsg.name}\033[0m")
        rules = nsg.security_rules or []
        if rules:
            ok(f"  {len(rules)} custom rule(s):")
            for rule in sorted(rules, key=lambda r: r.priority):
                direction = rule.direction
                access = rule.access
                color = "\033[92m" if access == "Allow" else "\033[91m"
                print(
                    f"      {color}[{access}]\033[0m  "
                    f"Priority {rule.priority:4d}  "
                    f"{direction:8s}  "
                    f"Port {rule.destination_port_range:6s}  "
                    f"From {rule.source_address_prefix}  "
                    f"— {rule.name}"
                )
        else:
            info("  No custom rules (using Azure defaults only)")


def check_nat_gateway(client: NetworkManagementClient, rg: str) -> None:
    section("4. NAT Gateway")
    nat_gws = list(client.nat_gateways.list(rg))
    if not nat_gws:
        fail("No NAT Gateways found in resource group")
        return

    for nat in nat_gws:
        ok(f"NAT Gateway: {nat.name}")
        ok(f"SKU: {nat.sku.name}")
        ok(f"Idle timeout: {nat.idle_timeout_in_minutes} minutes")
        ok(f"Provisioning state: {nat.provisioning_state}")

        if nat.public_ip_addresses:
            for pip_ref in nat.public_ip_addresses:
                pip_name = pip_ref.id.split("/")[-1]
                pip_rg = pip_ref.id.split("/")[4]
                try:
                    pip = client.public_ip_addresses.get(pip_rg, pip_name)
                    ok(f"Public IP: {pip.ip_address} ({pip.name})")
                except Exception:
                    info(f"Public IP ref: {pip_name} (could not resolve IP)")
        else:
            fail("No public IP associated with NAT Gateway")

        if nat.subnets:
            ok(f"Attached to {len(nat.subnets)} subnet(s)")
        else:
            fail("NAT Gateway not attached to any subnet")


def check_route_tables(client: NetworkManagementClient, rg: str) -> None:
    section("5. Route Tables")
    rts = list(client.route_tables.list(rg))
    if not rts:
        info("No custom route tables found (using Azure default routing)")
        return

    ok(f"Found {len(rts)} route table(s)")
    for rt in rts:
        print(f"\n    Route Table: \033[1m{rt.name}\033[0m")
        routes = rt.routes or []
        if routes:
            for route in routes:
                info(f"  {route.name}: {route.address_prefix} → {route.next_hop_type}")
        else:
            info("  No custom routes")

        subnets = rt.subnets or []
        if subnets:
            ok(f"  Associated with {len(subnets)} subnet(s)")
        else:
            fail("  Not associated with any subnet")


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Azure VNet configuration checker")
    parser.add_argument("--resource-group", required=True, help="Resource group name")
    parser.add_argument("--vnet-name", required=True, help="VNet name")
    parser.add_argument("--subscription-id", help="Azure subscription ID (uses default if omitted)")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════╗")
    print("║          Azure VNet Connectivity Report              ║")
    print("╚══════════════════════════════════════════════════════╝")

    # Authenticate using DefaultAzureCredential
    # Works with: az login, managed identity, service principal env vars
    credential = DefaultAzureCredential()

    # Get subscription ID
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

    client = NetworkManagementClient(credential, subscription_id)

    # Run all checks
    vnet = check_vnet(client, args.resource_group, args.vnet_name)
    if vnet is None:
        print("\n\033[91mAborting — VNet not found.\033[0m\n")
        sys.exit(1)

    check_subnets(client, args.resource_group, args.vnet_name)
    check_nsgs(client, args.resource_group)
    check_nat_gateway(client, args.resource_group)
    check_route_tables(client, args.resource_group)

    print(f"\n{'═' * 55}")
    print("  Report complete.")
    print(f"{'═' * 55}\n")


if __name__ == "__main__":
    main()
