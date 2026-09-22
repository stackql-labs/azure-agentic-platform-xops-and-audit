#!/usr/bin/env bash
# Fills AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_DEPLOYMENT and AZURE_OPENAI_API_KEY in
# .env from the Azure OpenAI account and deployment the xops stack created, so
# the agents (demo 3) can run. The key comes from list_keys (a POST, so an EXEC;
# the CLI only shows its response body in the http log, so that is where it is
# read from) and is written straight to .env: it never appears in a prompt or
# an agent log. Run from the repo root after `stackql-deploy build xops <env>`.
#   scripts/openai-env.sh [dev|prd]
set -euo pipefail
env=${1:-dev}
set -a; . ./.env; set +a
sub="$AZURE_SUBSCRIPTION_ID"
rg="xops-${env}-rg"
account="xops-${env}-openai-${sub:0:8}"

# the accounts list endpoint pages with an empty first page, so get by name
endpoint=$(stackql exec --output csv -H \
  "SELECT endpoint FROM azure.cognitive_services.accounts
   WHERE subscription_id = '${sub}' AND resource_group_name = '${rg}' AND account_name = '${account}'" \
  | tr -d '\r"')
deployment=$(stackql exec --output csv -H \
  "SELECT name FROM azure.cognitive_services.deployments
   WHERE subscription_id = '${sub}' AND resource_group_name = '${rg}' AND account_name = '${account}'" \
  | head -1 | tr -d '\r"')
key=$(stackql exec --http.log.enabled \
  "EXEC azure.cognitive_services.accounts.list_keys
   @account_name = '${account}', @resource_group_name = '${rg}', @subscription_id = '${sub}'" 2>&1 \
  | grep -o '"key1":"[^"]*"' | head -1 | cut -d'"' -f4)

[ -n "$endpoint" ] || { echo "no endpoint for ${account} in ${rg} (has the stack been built?)" >&2; exit 1; }
[ -n "$deployment" ] || { echo "no deployment under ${account} (has the stack been built?)" >&2; exit 1; }
[ -n "$key" ] || { echo "list_keys returned no key1 for ${account}" >&2; exit 1; }

# replace or append the three variables
for pair in "AZURE_OPENAI_ENDPOINT=${endpoint}" "AZURE_OPENAI_DEPLOYMENT=${deployment}" "AZURE_OPENAI_API_KEY=${key}"; do
  name=${pair%%=*}
  if grep -q "^${name}=" .env; then
    sed -i "s|^${name}=.*|${pair}|" .env
  else
    printf '%s\n' "$pair" >> .env
  fi
done
echo "AZURE_OPENAI_ENDPOINT=${endpoint}"
echo "AZURE_OPENAI_DEPLOYMENT=${deployment}"
echo "AZURE_OPENAI_API_KEY=<written to .env>"
