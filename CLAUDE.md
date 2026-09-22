# CLAUDE.md

Demo assets for "Azure as data: SQL-native provisioning and agentic platform ops (SRE, FinOps, audit) on Azure with StackQL", a 30 minute live demo for a Microsoft audience. See [README.md](README.md) for the running order.

## Layout

| Path | What it is |
| --- | --- |
| `xops/` | Demo 2: the service footprint as a `stackql-deploy` stack (`azure` + `cloudflare`): resource group, vnet, subnet, nsg, public ip, nic, vm + custom script, storage account, log analytics, two planted FinOps orphans, Azure OpenAI account + gpt-5-mini deployment, Cloudflare A record, conformance query |
| `demo/azure-provider/` | Demo 1: `stackql shell` and `exec` walkthroughs of the `azure` and `cloudflare` providers, ending in the cross-provider join |
| `demo/agentic-use-cases/` | Demo 3: Copilot (VS Code agent mode / Copilot CLI) prompts over the StackQL MCP server in `safe` mode, plus two Microsoft Agent Framework agents in `read_only` mode: FinOps analyst (Python) and SRE assurance (C#) on the stack's Azure OpenAI deployment |
| `.vscode/mcp.json`, `.github/mcp.json` | The `stackql` MCP server for VS Code Copilot and the Copilot CLI (`stackql mcp`, `--env.file .env`, `safe` mode) |
| `.github/copilot-instructions.md` | Discovery-first rules Copilot follows when it uses the stackql tools |
| `scripts/` | `register-providers.sh` (one-off: registers OperationalInsights, CognitiveServices, Advisor), `openai-env.sh` (writes the Azure OpenAI endpoint, deployment and key into `.env`), `vm.sh` (status, start, deallocate) |

## Environment

All credentials and stack variables live in the gitignored `.env` at the repo root (`.env.example` lists them). Source it with export semantics before running anything:

```bash
set -a; source .env; set +a
```

`stackql-deploy` also reads `.env` from the working directory (`--env-file`) for the manifest globals; the MCP configs pass `--env.file .env` so the server process gets the credentials without the model ever seeing them. The Azure service principal is Contributor on the subscription (it cannot create role assignments, which is why the agents use the Azure OpenAI account key rather than Entra ID).

stackql's app root (`--approot`, where `REGISTRY PULL` puts providers) defaults to `./.stackql` under the current directory. Run `stackql` from the repo root, or pass `--approot`; the MCP configs and the agents do.

## Working on the stack

- Run builds from the repo root: `stackql-deploy build xops dev --show-queries`. Builds are idempotent; `--dry-run` renders every query without executing. A first build is about 6 minutes (vm, Azure OpenAI account and deployment are asynchronous); a no-op re-run about 1 minute.
- Environments are `dev` and `prd`; per-environment values are `values:` blocks in the manifest. Same manifest and resource files for both.
- Filtering on a `json_each` alias in WHERE does not plan (`alias 't' does not map to any table expression`); filter on provider columns inside the CTE and keep json_each columns to SELECT and ORDER BY. `ORDER BY` an aggregate alias does not plan either; order by the expression.
- Resource files follow exists -> statecheck -> create, with list-based `exists` (`name = ...` over the resource group's list) so an absent resource is zero rows, not a 404. The nsg is `createorupdate` (drift repair on every build); the storage account and the DNS record have `update` anchors.
- The vm size must be one `azure.compute.resource_skus` reports without restrictions for the subscription in eastus2 (the B series is not; the F-series v7 is).
- Never commit `.env`, `.stackql/`, `*.log` or `.stackql-deploy-exports` (all gitignored).

## Working on the agents

- The agents load no SQL from files: the model writes SQL itself. Prompts name the exact `provider.service.resource` and columns so the model goes straight to `run_select_query`; open-ended discovery (`describe_resource` with big row limits) made a run take 10 minutes and blow the deployment's token-per-minute limit.
- The server's `read_only` guard refuses a SELECT whose first token is a `--` comment (`refused: server is in 'read_only' mode`). Both agents' instructions say the first token of every query is SELECT; this is an engine bug to raise upstream (stackql/stackql), not a manifest issue.
- Reasoning effort is `low` in both agents (`default_options={"reasoning": {"effort": "low"}}` in Python, `ChatOptions.Reasoning` in .NET); gpt-5-mini at the default effort is slow for a live demo.
- Model ids and endpoints come from `.env` only (`AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`, `AZURE_OPENAI_API_KEY`); never hardcode them.
- Both programmatic agents launch the server in `read_only` mode in code; the interactive hosts use `safe` mode from the MCP configs. Keep it that way: agency is a property of the process, not the prompt.
- Python: `agent-framework-core` + `agent-framework-openai` (the `agent-framework` meta package fails to install on Windows without long path support). .NET: `Microsoft.Agents.AI.OpenAI` + `Azure.AI.OpenAI` + `ModelContextProtocol`; the agent factory is `ChatClient.AsAIAgent(...)`.

## Copy and narrative

Matter of fact, no hyperbole. "Cloud and SaaS providers as data sources accessed via SQL", not "cloud as SQL tables". Use `-` not em dashes and `->` not arrow glyphs. No stacked headings.
