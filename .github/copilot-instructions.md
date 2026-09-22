# Copilot instructions for this repo

This repo is a StackQL demo on Azure. The `stackql` MCP server (configured in `.github/mcp.json` for the Copilot CLI and `.vscode/mcp.json` for VS Code) exposes cloud and SaaS providers as data sources accessed via SQL. Objects are `<provider>.<service>.<resource>`; queries are live API calls, not stored data.

When asked about the estate, use the stackql tools:

- Discover before you write SQL: `list_resources`, `describe_resource`, `list_methods`. Do not guess table or column names.
- Reads are `run_select_query`. Azure resources take `subscription_id` (and usually `resource_group_name`) in the WHERE clause; Cloudflare DNS records take `zone_id`.
- Writes (`run_mutation_query`, `run_lifecycle_operation`) are gated: the server runs in `safe` mode and asks a human before each one. Propose the exact SQL, then run it once approved, then re-query to confirm.
- The first token of every query is `SELECT` (no leading `--` comments: the server's guard rejects them); the dialect is SQLite (`LIMIT`, not `TOP`).
- JSON columns are unpacked with `JSON_EXTRACT` and `json_each` (filter on provider columns inside a CTE, not on the `json_each` alias); booleans compare as 0/1; numeric columns arrive as text (cast in a subquery).
- Azure resource providers `azure.cognitive_services.accounts` list pages with an empty first page: query that resource with `account_name = ...`.
- Report findings as a short plain-text table with one line of SQL evidence each.

The demo stack is `xops` (see `xops/stackql_manifest.yml`): resource group `xops-dev-rg` in `eastus2`, subscription id in `.env` as `AZURE_SUBSCRIPTION_ID`, DNS record `azure-demo.stackql.xyz` in Cloudflare.
