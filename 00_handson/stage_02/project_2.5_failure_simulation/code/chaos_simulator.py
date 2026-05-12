"""
chaos_simulator.py — Azure failure simulation tool.

Actions:
    stop-vm          Deallocate a random (or named) VM
    block-nsg        Remove all Allow rules from an NSG
    simulate-db-fail Trigger Azure SQL failover
    restore          Undo all chaos actions from rollback.json

Usage:
    python chaos_simulator.py stop-vm --resource-group rg-chaos-lab
    python chaos_simulator.py stop-vm --resource-group rg-chaos-lab --vm-name vm-chaos-target
    python chaos_simulator.py block-nsg --resource-group rg-chaos-lab --nsg-name nsg-chaos
    python chaos_simulator.py simulate-db-fail --resource-group rg-chaos-lab
    python chaos_simulator.py restore --resource-group rg-chaos-lab

Requirements:
    pip install azure-mgmt-compute azure-mgmt-network azure-mgmt-sql azure-identity
"""

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.sql import SqlManagementClient


ROLLBACK_FILE = "rollback.json"


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

def chaos(msg: str) -> None:
    print(f"  \033[91m💥\033[0m  {msg}")

def section(title: str) -> None:
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


# ─────────────────────────────────────────────
# Rollback log
# ─────────────────────────────────────────────

def load_rollback() -> dict:
    if Path(ROLLBACK_FILE).exists():
        with open(ROLLBACK_FILE) as f:
            return json.load(f)
    return {"actions": [], "started_at": datetime.utcnow().isoformat()}


def save_rollback(data: dict) -> None:
    with open(ROLLBACK_FILE, "w") as f:
        json.dump(data, f, indent=2)
    info(f"Rollback log saved to {ROLLBACK_FILE}")


def append_rollback(action: dict) -> None:
    data = load_rollback()
    data["actions"].append({**action, "timestamp": datetime.utcnow().isoformat()})
    save_rollback(data)


# ─────────────────────────────────────────────
# Action: stop-vm
# ─────────────────────────────────────────────

def action_stop_vm(
    compute_client: ComputeManagementClient,
    resource_group: str,
    vm_name: str | None,
) -> None:
    section("Chaos Action: Stop VM")

    # Find target VM
    if vm_name:
        vms = [compute_client.virtual_machines.get(resource_group, vm_name, expand="instanceView")]
    else:
        all_vms = list(compute_client.virtual_machines.list(resource_group))
        if not all_vms:
            fail("No VMs found in resource group")
            return
        vms = [all_vms[0]]  # Pick first VM
        info(f"No VM name specified — targeting: {vms[0].name}")

    for vm in vms:
        chaos(f"Deallocating VM: {vm.name}")
        info("This will stop billing for compute but lose ephemeral state")

        # Save rollback action
        append_rollback({
            "type": "start_vm",
            "resource_group": resource_group,
            "vm_name": vm.name,
        })

        # Deallocate
        poller = compute_client.virtual_machines.begin_deallocate(resource_group, vm.name)
        info("Waiting for deallocation to complete...")
        poller.wait()

        # Verify
        vm_detail = compute_client.virtual_machines.get(
            resource_group, vm.name, expand="instanceView"
        )
        statuses = vm_detail.instance_view.statuses if vm_detail.instance_view else []
        power_state = next(
            (s.display_status for s in statuses if s.code and s.code.startswith("PowerState")),
            "Unknown"
        )
        ok(f"VM {vm.name} is now: {power_state}")
        warn("SSH and HTTP connections to this VM will now fail")


# ─────────────────────────────────────────────
# Action: block-nsg
# ─────────────────────────────────────────────

def action_block_nsg(
    network_client: NetworkManagementClient,
    resource_group: str,
    nsg_name: str | None,
) -> None:
    section("Chaos Action: Block NSG")

    # Find target NSG
    if nsg_name:
        nsg = network_client.network_security_groups.get(resource_group, nsg_name)
        nsgs = [nsg]
    else:
        nsgs = list(network_client.network_security_groups.list(resource_group))
        if not nsgs:
            fail("No NSGs found in resource group")
            return
        nsgs = [nsgs[0]]
        info(f"No NSG name specified — targeting: {nsgs[0].name}")

    for nsg in nsgs:
        rules = nsg.security_rules or []
        allow_rules = [r for r in rules if r.access == "Allow"]

        if not allow_rules:
            warn(f"NSG {nsg.name} has no Allow rules to remove")
            continue

        chaos(f"Removing {len(allow_rules)} Allow rule(s) from NSG: {nsg.name}")

        # Save rollback action with full rule details
        rollback_rules = []
        for rule in allow_rules:
            rollback_rules.append({
                "name": rule.name,
                "priority": rule.priority,
                "direction": rule.direction,
                "access": rule.access,
                "protocol": rule.protocol,
                "source_port_range": rule.source_port_range,
                "destination_port_range": rule.destination_port_range,
                "source_address_prefix": rule.source_address_prefix,
                "destination_address_prefix": rule.destination_address_prefix,
            })

        append_rollback({
            "type": "restore_nsg_rules",
            "resource_group": resource_group,
            "nsg_name": nsg.name,
            "rules": rollback_rules,
        })

        # Delete each Allow rule
        for rule in allow_rules:
            info(f"  Deleting rule: {rule.name} (priority {rule.priority})")
            poller = network_client.security_rules.begin_delete(
                resource_group, nsg.name, rule.name
            )
            poller.wait()

        ok(f"All Allow rules removed from {nsg.name}")
        warn("All inbound traffic to associated subnets is now blocked")


# ─────────────────────────────────────────────
# Action: simulate-db-fail
# ─────────────────────────────────────────────

def action_simulate_db_fail(
    sql_client: SqlManagementClient,
    resource_group: str,
) -> None:
    section("Chaos Action: Simulate DB Failure")

    servers = list(sql_client.servers.list_by_resource_group(resource_group))
    if not servers:
        fail("No Azure SQL servers found in resource group")
        return

    server = servers[0]
    databases = list(sql_client.databases.list_by_server(resource_group, server.name))
    user_dbs = [db for db in databases if db.name != "master"]

    if not user_dbs:
        fail(f"No user databases found on server {server.name}")
        return

    db = user_dbs[0]
    chaos(f"Triggering failover on: {server.name}/{db.name}")
    info("Connections will fail for approximately 20–30 seconds")
    info("Applications need retry logic with exponential backoff to handle this")

    # Save rollback note (failover is self-healing, no explicit restore needed)
    append_rollback({
        "type": "db_failover_note",
        "resource_group": resource_group,
        "server_name": server.name,
        "database_name": db.name,
        "note": "Azure SQL failover is self-healing. No explicit restore action needed.",
    })

    try:
        # Trigger failover
        poller = sql_client.databases.begin_failover(resource_group, server.name, db.name)
        info("Failover initiated. Waiting for completion...")
        poller.wait()
        ok(f"Failover completed for {db.name}")
        info("Database is back online. Connection strings remain the same.")
    except Exception as e:
        # Basic tier doesn't support manual failover — simulate the effect
        warn(f"Manual failover not supported on this tier: {e}")
        info("Simulating DB unavailability by pausing database (if supported)...")
        try:
            # Pause (only works on serverless tier)
            sql_client.databases.begin_pause(resource_group, server.name, db.name).wait()
            ok("Database paused (simulating failure)")
            append_rollback({
                "type": "resume_db",
                "resource_group": resource_group,
                "server_name": server.name,
                "database_name": db.name,
            })
        except Exception as e2:
            warn(f"Pause also not supported: {e2}")
            info("For Basic/Standard tier, test DB failure by temporarily blocking the firewall rule")


# ─────────────────────────────────────────────
# Action: restore
# ─────────────────────────────────────────────

def action_restore(
    compute_client: ComputeManagementClient,
    network_client: NetworkManagementClient,
    sql_client: SqlManagementClient,
    resource_group: str,
) -> None:
    section("Restore: Undoing All Chaos Actions")

    data = load_rollback()
    actions = data.get("actions", [])

    if not actions:
        warn("No rollback actions found. Nothing to restore.")
        return

    info(f"Found {len(actions)} action(s) to reverse")

    # Process in reverse order
    for action in reversed(actions):
        action_type = action.get("type")
        info(f"Reversing: {action_type}")

        if action_type == "start_vm":
            vm_name = action["vm_name"]
            info(f"  Starting VM: {vm_name}")
            poller = compute_client.virtual_machines.begin_start(resource_group, vm_name)
            poller.wait()
            ok(f"  VM {vm_name} started")

        elif action_type == "restore_nsg_rules":
            nsg_name = action["nsg_name"]
            rules = action["rules"]
            info(f"  Restoring {len(rules)} NSG rule(s) to {nsg_name}")
            for rule_data in rules:
                from azure.mgmt.network.models import SecurityRule
                rule = SecurityRule(
                    name=rule_data["name"],
                    priority=rule_data["priority"],
                    direction=rule_data["direction"],
                    access=rule_data["access"],
                    protocol=rule_data["protocol"],
                    source_port_range=rule_data["source_port_range"],
                    destination_port_range=rule_data["destination_port_range"],
                    source_address_prefix=rule_data["source_address_prefix"],
                    destination_address_prefix=rule_data["destination_address_prefix"],
                )
                poller = network_client.security_rules.begin_create_or_update(
                    resource_group, nsg_name, rule_data["name"], rule
                )
                poller.wait()
                ok(f"  Restored rule: {rule_data['name']}")

        elif action_type == "resume_db":
            server_name = action["server_name"]
            db_name = action["database_name"]
            info(f"  Resuming database: {server_name}/{db_name}")
            try:
                sql_client.databases.begin_resume(resource_group, server_name, db_name).wait()
                ok(f"  Database {db_name} resumed")
            except Exception as e:
                warn(f"  Could not resume database: {e}")

        elif action_type == "db_failover_note":
            ok(f"  DB failover is self-healing — no action needed")

        else:
            warn(f"  Unknown action type: {action_type} — skipping")

    # Clear rollback file
    Path(ROLLBACK_FILE).unlink(missing_ok=True)
    ok("Rollback file cleared")
    ok("All chaos actions reversed")


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def get_subscription_id(credential) -> str:
    from azure.mgmt.subscription import SubscriptionClient
    sub_client = SubscriptionClient(credential)
    subscriptions = list(sub_client.subscriptions.list())
    if not subscriptions:
        print("\nERROR: No subscriptions found. Run 'az login' first.")
        sys.exit(1)
    return subscriptions[0].subscription_id


def main() -> None:
    parser = argparse.ArgumentParser(description="Azure chaos simulator")
    parser.add_argument(
        "action",
        choices=["stop-vm", "block-nsg", "simulate-db-fail", "restore"],
        help="Chaos action to perform",
    )
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--subscription-id", help="Azure subscription ID")
    parser.add_argument("--vm-name", help="Target VM name (stop-vm action)")
    parser.add_argument("--nsg-name", help="Target NSG name (block-nsg action)")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║              Azure Chaos Simulator                       ║")
    print(f"║  Action: {args.action:<48}║")
    print("╚══════════════════════════════════════════════════════════╝")
    warn("This tool deliberately breaks Azure resources for learning purposes.")
    warn("Always run 'restore' when done to undo all changes.")
    print()

    credential = DefaultAzureCredential()
    subscription_id = args.subscription_id or get_subscription_id(credential)

    compute_client = ComputeManagementClient(credential, subscription_id)
    network_client = NetworkManagementClient(credential, subscription_id)
    sql_client = SqlManagementClient(credential, subscription_id)

    if args.action == "stop-vm":
        action_stop_vm(compute_client, args.resource_group, args.vm_name)
    elif args.action == "block-nsg":
        action_block_nsg(network_client, args.resource_group, args.nsg_name)
    elif args.action == "simulate-db-fail":
        action_simulate_db_fail(sql_client, args.resource_group)
    elif args.action == "restore":
        action_restore(compute_client, network_client, sql_client, args.resource_group)

    print(f"\n{'═' * 60}")
    print(f"  Action '{args.action}' complete.")
    if args.action != "restore":
        print(f"  Run 'restore' to undo: python chaos_simulator.py restore --resource-group {args.resource_group}")
    print(f"{'═' * 60}\n")


if __name__ == "__main__":
    main()
