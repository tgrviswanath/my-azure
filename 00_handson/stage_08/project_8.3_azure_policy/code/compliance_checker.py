"""
compliance_checker.py — Check Azure Policy compliance status.

Usage:
    pip install azure-identity azure-mgmt-policyinsights azure-mgmt-resource
    python code/compliance_checker.py
"""

import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.policyinsights import PolicyInsightsClient
from azure.mgmt.resource import SubscriptionClient


def check_compliance() -> None:
    credential = DefaultAzureCredential()
    sub_client = SubscriptionClient(credential)
    subscription_id = list(sub_client.subscriptions.list())[0].subscription_id

    policy_client = PolicyInsightsClient(credential)

    print(f"\n{'='*65}")
    print(f"  Azure Policy Compliance Report")
    print(f"{'='*65}")
    print(f"  Subscription: {subscription_id}\n")

    # Get policy states summary
    summary = policy_client.policy_states.summarize_for_subscription(
        subscription_id=subscription_id
    )

    for s in summary.value:
        results = s.results
        print(f"  Total resources evaluated : {results.resource_details.total_count}")
        print(f"  Non-compliant resources   : {results.resource_details.non_compliant_count}")
        print(f"  Compliant resources       : {results.resource_details.compliant_count}")

        if results.policy_details:
            print(f"\n  Non-compliant policies: {results.policy_details.non_compliant_count}")

    # List non-compliant resources
    print(f"\n  {'Policy':<40} {'Resource':<30} {'State'}")
    print(f"  {'-'*40} {'-'*30} {'-'*15}")

    states = policy_client.policy_states.list_query_results_for_subscription(
        policy_states_resource="latest",
        subscription_id=subscription_id,
        query_options={"filter": "complianceState eq 'NonCompliant'", "top": 20}
    )

    count = 0
    for state in states:
        policy_name = (state.policy_definition_name or "")[:38]
        resource = (state.resource_id or "").split("/")[-1][:28]
        print(f"  {policy_name:<40} {resource:<30} NON_COMPLIANT")
        count += 1

    if count == 0:
        print(f"  ✅ All resources are compliant!")
    else:
        print(f"\n  ⚠️  {count} non-compliant resource(s) found.")
        print(f"  Run remediation: az policy remediation create --policy-assignment <id>")

    print(f"{'='*65}\n")


if __name__ == "__main__":
    check_compliance()
