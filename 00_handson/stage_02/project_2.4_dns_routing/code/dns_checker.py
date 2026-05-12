"""
dns_checker.py — Check Azure DNS zones and Traffic Manager configuration.

Usage:
    python dns_checker.py --resource-group rg-dns-lab
    python dns_checker.py --resource-group rg-dns-lab --subscription-id <id>

Requirements:
    pip install azure-mgmt-dns azure-mgmt-trafficmanager azure-identity
"""

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.dns import DnsManagementClient
from azure.mgmt.trafficmanager import TrafficManagerManagementClient


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
# DNS Zone checks
# ─────────────────────────────────────────────

def check_dns_zones(dns_client: DnsManagementClient, resource_group: str) -> None:
    section("1. Azure DNS Zones")
    zones = list(dns_client.zones.list_by_resource_group(resource_group))

    if not zones:
        warn("No DNS zones found in resource group")
        return

    ok(f"Found {len(zones)} DNS zone(s)")
    for zone in zones:
        print(f"\n    Zone: \033[1m{zone.name}\033[0m")
        info(f"  Type: {zone.zone_type}")
        info(f"  Number of record sets: {zone.number_of_record_sets}")
        info(f"  Max record sets: {zone.max_number_of_record_sets}")

        if zone.name_servers:
            ok(f"  Name servers ({len(zone.name_servers)}):")
            for ns in zone.name_servers:
                print(f"      → {ns}")

        # List record sets
        records = list(dns_client.record_sets.list_by_dns_zone(resource_group, zone.name))
        print(f"\n    Records ({len(records)}):")
        print(f"    {'Name':<30} {'Type':<8} {'TTL':>6}  {'Value'}")
        print(f"    {'─' * 70}")
        for record in records:
            rtype = record.type.split("/")[-1] if record.type else "?"
            name = record.name or "@"
            ttl = record.ttl or 0
            value = _get_record_value(record, rtype)
            print(f"    {name:<30} {rtype:<8} {ttl:>6}  {value}")


def _get_record_value(record, rtype: str) -> str:
    """Extract the record value for display."""
    try:
        if rtype == "A" and record.a_records:
            return ", ".join(r.ipv4_address for r in record.a_records)
        elif rtype == "AAAA" and record.aaaa_records:
            return ", ".join(r.ipv6_address for r in record.aaaa_records)
        elif rtype == "CNAME" and record.cname_record:
            return record.cname_record.cname or ""
        elif rtype == "MX" and record.mx_records:
            return ", ".join(f"{r.preference} {r.exchange}" for r in record.mx_records)
        elif rtype == "TXT" and record.txt_records:
            return " | ".join(" ".join(r.value) for r in record.txt_records)[:60]
        elif rtype == "NS" and record.ns_records:
            return ", ".join(r.nsdname for r in record.ns_records)
        elif rtype == "SOA" and record.soa_record:
            return f"host={record.soa_record.host}"
        else:
            return "(see portal)"
    except Exception:
        return "(error reading value)"


# ─────────────────────────────────────────────
# Traffic Manager checks
# ─────────────────────────────────────────────

def check_traffic_manager(
    tm_client: TrafficManagerManagementClient,
    resource_group: str,
) -> None:
    section("2. Traffic Manager Profiles")
    profiles = list(tm_client.profiles.list_by_resource_group(resource_group))

    if not profiles:
        warn("No Traffic Manager profiles found in resource group")
        return

    ok(f"Found {len(profiles)} profile(s)")
    for profile in profiles:
        print(f"\n    Profile: \033[1m{profile.name}\033[0m")

        status = profile.profile_status or "Unknown"
        if status == "Enabled":
            ok(f"  Status: {status}")
        else:
            fail(f"  Status: {status}")

        routing = profile.traffic_routing_method or "Unknown"
        ok(f"  Routing method: {routing}")
        info(f"  FQDN: {profile.dns_config.fqdn if profile.dns_config else 'N/A'}")
        info(f"  TTL: {profile.dns_config.ttl if profile.dns_config else 'N/A'}s")

        # Monitor config
        if profile.monitor_config:
            mc = profile.monitor_config
            info(f"  Health probe: {mc.protocol}:{mc.port}{mc.path} every {mc.interval_in_seconds}s")
            info(f"  Failure threshold: {mc.tolerated_number_of_failures} consecutive failures")

        # Endpoints
        endpoints = profile.endpoints or []
        print(f"\n    Endpoints ({len(endpoints)}):")
        print(f"    {'Name':<30} {'Priority':>8} {'Weight':>7} {'Status':<12} {'Target'}")
        print(f"    {'─' * 80}")

        for ep in sorted(endpoints, key=lambda e: e.priority or 999):
            ep_status = ep.endpoint_status or "Unknown"
            ep_monitor = ep.endpoint_monitor_status or "Unknown"
            priority = ep.priority or "-"
            weight = ep.weight or "-"
            target = ep.target or (ep.target_resource_id.split("/")[-1] if ep.target_resource_id else "N/A")

            # Color by monitor status
            if ep_monitor in ("Online", "CheckingEndpoint"):
                status_str = f"\033[92m{ep_monitor}\033[0m"
            elif ep_monitor in ("Degraded", "Inactive"):
                status_str = f"\033[91m{ep_monitor}\033[0m"
            else:
                status_str = f"\033[93m{ep_monitor}\033[0m"

            print(f"    {ep.name:<30} {str(priority):>8} {str(weight):>7} {status_str:<20} {target}")

        # Routing method explanation
        print(f"\n    Routing explanation:")
        explanations = {
            "Priority": "  Traffic goes to highest-priority healthy endpoint. Failover to next on failure.",
            "Weighted": "  Traffic distributed proportionally by weight values.",
            "Performance": "  Traffic routed to endpoint with lowest latency for the client.",
            "Geographic": "  Traffic routed based on client's geographic location.",
            "Multivalue": "  All healthy endpoints returned in DNS response.",
            "Subnet": "  Traffic routed based on client IP address range.",
        }
        explanation = explanations.get(routing, "  Unknown routing method.")
        info(explanation)


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Azure DNS and Traffic Manager checker")
    parser.add_argument("--resource-group", required=True, help="Resource group name")
    parser.add_argument("--subscription-id", help="Azure subscription ID")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║           Azure DNS + Traffic Manager Report             ║")
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

    dns_client = DnsManagementClient(credential, subscription_id)
    tm_client = TrafficManagerManagementClient(credential, subscription_id)

    check_dns_zones(dns_client, args.resource_group)
    check_traffic_manager(tm_client, args.resource_group)

    print(f"\n{'═' * 60}")
    print("  Report complete.")
    print(f"{'═' * 60}\n")


if __name__ == "__main__":
    main()
