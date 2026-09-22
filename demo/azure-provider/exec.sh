# =============================================================================
# stackql exec - one-shot queries with output options
# copy and paste one block at a time (not a batch script)
# prereqs: AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET,
#          AZURE_SUBSCRIPTION_ID, CLOUDFLARE_API_TOKEN
#          (set -a; source .env; set +a  from the repo root)
# =============================================================================

# default output (table) to stdout: the resource group's inventory
stackql exec \
"SELECT name, type, location
 FROM azure.resource.resources
 WHERE subscription_id = '$AZURE_SUBSCRIPTION_ID'
 AND resource_group_name = 'xops-dev-rg'
 ORDER BY type, name"

# json to stdout (pipe into jq)
stackql exec --output json \
"SELECT name, JSON_EXTRACT(hardware_profile, '\$.vmSize') AS size, provisioning_state
 FROM azure.compute.virtual_machines
 WHERE subscription_id = '$AZURE_SUBSCRIPTION_ID'
 AND resource_group_name = 'xops-dev-rg'" | jq .

# jsonl (one object per line) written to a file: the FinOps waste list
stackql exec --output jsonl -f demo/azure-provider/orphans.jsonl \
"SELECT name, disk_state, disk_size_gb, JSON_EXTRACT(sku, '\$.name') AS sku
 FROM azure.compute.disks
 WHERE subscription_id = '$AZURE_SUBSCRIPTION_ID'
 AND resource_group_name = 'xops-dev-rg'
 AND disk_state = 'Unattached'"
cat demo/azure-provider/orphans.jsonl

# csv with headers to a file: storage posture for the auditors
stackql exec --output csv -f demo/azure-provider/storage-posture.csv \
"SELECT name, allow_blob_public_access, minimum_tls_version, supports_https_traffic_only
 FROM azure.storage.storage_accounts
 WHERE subscription_id = '$AZURE_SUBSCRIPTION_ID'
 AND resource_group_name = 'xops-dev-rg'"
cat demo/azure-provider/storage-posture.csv

# csv, pipe-delimited, headers suppressed (-H): public ips for a downstream script
stackql exec --output csv -f demo/azure-provider/public-ips.psv -H -d="|" \
"SELECT name, ip_address
 FROM azure.network.public_ip_addresses
 WHERE subscription_id = '$AZURE_SUBSCRIPTION_ID'
 AND resource_group_name = 'xops-dev-rg'"
cat demo/azure-provider/public-ips.psv

# queries from a file (-i) with a jsonnet config (--iqldata) and an external var (--var)
# vars.jsonnet carries the subscription id and the resource group
stackql exec -i demo/azure-provider/queries/exposure.iql \
  --iqldata demo/azure-provider/queries/vars.jsonnet \
  --var subscription_id=$AZURE_SUBSCRIPTION_ID --output csv

# the cross-provider join from a file: edge record -> azure public ip -> what it is attached to
stackql exec -i demo/azure-provider/queries/edge-to-origin.iql \
  --iqldata demo/azure-provider/queries/vars.jsonnet \
  --var subscription_id=$AZURE_SUBSCRIPTION_ID --output table

# preview the rendered SQL without executing anything (--dryrun)
stackql exec -i demo/azure-provider/queries/edge-to-origin.iql \
  --iqldata demo/azure-provider/queries/vars.jsonnet \
  --var subscription_id=$AZURE_SUBSCRIPTION_ID --dryrun --output text
