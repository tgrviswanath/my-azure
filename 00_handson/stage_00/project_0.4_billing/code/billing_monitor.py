"""
billing_monitor.py — Monitor Azure costs using the Cost Management SDK.

Prerequisites:
    pip install azure-mgmt-costmanagement azure-identity azure-mgmt-consumption

Authentication:
    az login   (uses DefaultAzureCredential)

Run:
    python code/billing_monitor.py
"""

import os
from datetime import datetime, timedelta
from azure.identity import DefaultAzureCredential
from azure.mgmt.costmanagement import CostManagementClient
from azure.mgmt.consumption import ConsumptionManagementClient


def get_subscription_id() -> str:
    """Get subscription ID from environment or Azure CLI."""
    sub_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
    if not sub_id:
        import subprocess
        result = subprocess.run(
            ["az", "account", "show", "--query", "id", "-o", "tsv"],
            capture_output=True, text=True
        )
        sub_id = result.stdout.strip()
    if not sub_id:
        raise ValueError("Set AZURE_SUBSCRIPTION_ID or run 'az login'")
    return sub_id


def get_current_month_dates() -> tuple[str, str]:
    """Return first and last day of current month in YYYY-MM-DD format."""
    today = datetime.utcnow()
    first_day = today.replace(day=1).strftime("%Y-%m-%d")
    last_day = today.strftime("%Y-%m-%d")
    return first_day, last_day


def query_cost_by_service(client: CostManagementClient, scope: str) -> None:
    """Query and display current month costs grouped by service."""
    start_date, end_date = get_current_month_dates()
    print(f"\n[*] Cost by Service ({start_date} to {end_date})")
    print("-" * 55)

    query = {
        "type": "ActualCost",
        "timeframe": "Custom",
        "time_period": {
            "from": f"{start_date}T00:00:00Z",
            "to": f"{end_date}T23:59:59Z"
        },
        "dataset": {
            "granularity": "None",
            "aggregation": {
                "totalCost": {
                    "name": "Cost",
                    "function": "Sum"
                }
            },
            "grouping": [
                {
                    "type": "Dimension",
                    "name": "ServiceName"
                }
            ]
        }
    }

    try:
        result = client.query.usage(scope=scope, parameters=query)
        rows = result.rows if result.rows else []

        if not rows:
            print("  No cost data available (may have 24-48h delay)")
            return

        # Sort by cost descending
        rows_sorted = sorted(rows, key=lambda x: float(x[0]), reverse=True)

        total = 0.0
        print(f"  {'Service':<35} {'Cost (USD)':>10}")
        print(f"  {'-'*35} {'-'*10}")
        for row in rows_sorted[:10]:  # Top 10 services
            cost = float(row[0])
            service = str(row[1]) if len(row) > 1 else "Unknown"
            total += cost
            print(f"  {service:<35} ${cost:>9.4f}")

        print(f"  {'-'*35} {'-'*10}")
        print(f"  {'TOTAL':<35} ${total:>9.4f}")

    except Exception as e:
        print(f"  [!] Could not query costs: {e}")
        print("  [!] Ensure you have Cost Management Reader role")


def query_cost_by_tag(client: CostManagementClient, scope: str) -> None:
    """Query costs grouped by environment tag."""
    start_date, end_date = get_current_month_dates()
    print(f"\n[*] Cost by Environment Tag ({start_date} to {end_date})")
    print("-" * 55)

    query = {
        "type": "ActualCost",
        "timeframe": "Custom",
        "time_period": {
            "from": f"{start_date}T00:00:00Z",
            "to": f"{end_date}T23:59:59Z"
        },
        "dataset": {
            "granularity": "None",
            "aggregation": {
                "totalCost": {
                    "name": "Cost",
                    "function": "Sum"
                }
            },
            "grouping": [
                {
                    "type": "TagKey",
                    "name": "environment"
                }
            ]
        }
    }

    try:
        result = client.query.usage(scope=scope, parameters=query)
        rows = result.rows if result.rows else []

        if not rows:
            print("  No tagged resources found or no cost data yet")
            return

        print(f"  {'Environment Tag':<25} {'Cost (USD)':>10}")
        print(f"  {'-'*25} {'-'*10}")
        for row in rows:
            cost = float(row[0])
            tag_val = str(row[1]) if len(row) > 1 else "untagged"
            print(f"  {tag_val:<25} ${cost:>9.4f}")

    except Exception as e:
        print(f"  [!] Could not query tag costs: {e}")


def list_budgets(consumption_client: ConsumptionManagementClient, scope: str) -> None:
    """List all budgets and their current status."""
    print("\n[*] Active Budgets")
    print("-" * 55)

    try:
        budgets = list(consumption_client.budgets.list(scope=scope))
        if not budgets:
            print("  No budgets configured. Create one with Terraform!")
            return

        for budget in budgets:
            amount = budget.amount
            current = budget.current_spend.amount if budget.current_spend else 0
            pct = (current / amount * 100) if amount > 0 else 0
            bar = "█" * int(pct / 10) + "░" * (10 - int(pct / 10))

            print(f"  Budget: {budget.name}")
            print(f"  Limit:  ${amount:.2f}/month")
            print(f"  Spent:  ${current:.4f} ({pct:.1f}%)")
            print(f"  [{bar}] {pct:.1f}%")
            print()

    except Exception as e:
        print(f"  [!] Could not list budgets: {e}")


def main():
    print("=" * 55)
    print("  Azure Billing Monitor")
    print("=" * 55)

    try:
        credential = DefaultAzureCredential()
        subscription_id = get_subscription_id()
        scope = f"/subscriptions/{subscription_id}"

        print(f"[*] Subscription: {subscription_id}")

        cost_client = CostManagementClient(credential, subscription_id)
        consumption_client = ConsumptionManagementClient(credential, subscription_id)

        query_cost_by_service(cost_client, scope)
        query_cost_by_tag(cost_client, scope)
        list_budgets(consumption_client, scope)

        print("\n[+] Done. Cost data has a 24-48 hour delay in Azure.")

    except Exception as e:
        print(f"\n[!] Error: {e}")
        print("[!] Run 'az login' and ensure you have Cost Management Reader role")


if __name__ == "__main__":
    main()
