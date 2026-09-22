#!/usr/bin/env bash
# One-off subscription setup: register the Azure resource providers the xops
# stack uses. A new subscription has Compute, Network and Storage registered
# and little else; creating a Log Analytics workspace or an Azure OpenAI
# account in an unregistered namespace fails with 409
# MissingSubscriptionRegistration. Registration is a lifecycle EXEC and takes
# about a minute; this waits for it. Run from the repo root.
set -euo pipefail
set -a; . ./.env; set +a
sub="$AZURE_SUBSCRIPTION_ID"
namespaces="Microsoft.OperationalInsights Microsoft.CognitiveServices Microsoft.Advisor"

for ns in $namespaces; do
  echo "registering ${ns}"
  stackql exec "EXEC azure.resource.providers.register
    @resource_provider_namespace = '${ns}', @subscription_id = '${sub}'" >/dev/null
done

for i in $(seq 1 30); do
  stackql exec "SELECT namespace, registration_state
    FROM azure.resource.providers
    WHERE subscription_id = '${sub}'
    AND namespace IN ('Microsoft.OperationalInsights', 'Microsoft.CognitiveServices', 'Microsoft.Advisor')"
  n=$(stackql exec --output csv -H "SELECT namespace FROM azure.resource.providers
    WHERE subscription_id = '${sub}'
    AND namespace IN ('Microsoft.OperationalInsights', 'Microsoft.CognitiveServices', 'Microsoft.Advisor')
    AND registration_state = 'Registered'" | grep -c Microsoft || true)
  [ "$n" -ge 3 ] && { echo "all registered"; exit 0; }
  sleep 10
done
echo "still registering after 5 minutes; check the Azure portal" >&2
exit 1
