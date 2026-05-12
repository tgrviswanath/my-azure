"""
security_monitor.py — Fetch Defender for Cloud security alerts and recommendations.

Usage:
    pip install azure-identity azure-mgmt-security
    python code/security_monitor.py
    python code/security_monitor.py --severity HIGH
"""

import argparse
from azure.identity import DefaultAzureCredential
from azure.mgmt.security import SecurityCenter
from azure.mgmt.resource import SubscriptionClient


def get_subscription_id() -> str:
    credential = DefaultAzureCredential()
    client = SubscriptionClient(credential)
    return list(client.subscriptions.list())[0].subscription_id


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--severity", choices=["HIGH", "MEDIUM", "LOW"])
    args = parser.parse_args()

    credential = DefaultAzureCredential()
    subscription_id = get_subscription_id()
    client = SecurityCenter(credential, subscription_id)

    print(f"\n{'='*60}")
    print(f"  Defender for Cloud Security Report")
    print(f"{'='*60}")

    # Security Score
    print("\n  Security Score:")
    for score in client.secure_scores.list():
        if score.display_name == "ASC Default" and score.score:
            pct = round((score.score.current / score.score.max) * 100, 1) if score.score.max else 0
            print(f"  Score: {score.score.current:.0f}/{score.score.max:.0f} ({pct}%)")

    # Security Alerts
    print("\n  Security Alerts:")
    print(f"  {'Alert':<40} {'Severity':<10} {'Status'}")
    print(f"  {'-'*40} {'-'*10} {'-'*10}")
    count = 0
    for alert in client.alerts.list():
        sev = str(alert.severity or "")
        if args.severity and args.severity.upper() not in sev.upper():
            continue
        name = (alert.alert_display_name or "")[:38]
        status = str(alert.status or "")
        print(f"  {name:<40} {sev:<10} {status}")
        count += 1

    if count == 0:
        print("  ✅ No active security alerts.")

    print(f"\n{'='*60}\n")


if __name__ == "__main__":
    main()
