#!/usr/bin/env bash
# Plants drift on the stack, the way it happens in real life: someone opens 22
# to the internet on the nsg and turns on public blob access on the storage
# account. The SRE agent (demo 3) finds both; `stackql-deploy build xops dev`
# puts both back (the nsg is createorupdate, the storage account has an update
# anchor). Run from the repo root.
set -euo pipefail
env=${1:-dev}
set -a; . ./.env; set +a
sub="$AZURE_SUBSCRIPTION_ID"
rg="xops-${env}-rg"
sa="xops${env}${sub:0:8}"

echo "1. nsg: allow 22 from the internet (a new rule, priority 150)"
stackql exec "INSERT INTO azure.network.security_rules(
  network_security_group_name, resource_group_name, security_rule_name, subscription_id, properties
)
SELECT 'xops-${env}-nsg', '${rg}', 'AllowSSHFromInternet', '${sub}',
       '{\"access\": \"Allow\", \"protocol\": \"Tcp\", \"direction\": \"Inbound\", \"priority\": 150, \"sourceAddressPrefix\": \"*\", \"sourcePortRange\": \"*\", \"destinationAddressPrefix\": \"*\", \"destinationPortRange\": \"22\"}'"

echo "2. storage account: allow public blob access"
stackql exec "UPDATE azure.storage.storage_accounts
SET properties = '{\"allowBlobPublicAccess\": true}'
WHERE subscription_id = '${sub}'
AND resource_group_name = '${rg}'
AND account_name = '${sa}'"

echo "drift planted. find it: demo 3 prompts or dotnet run --project demo/agentic-use-cases/dotnet-agent"
echo "repair it: stackql-deploy build xops ${env}"
