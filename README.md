# azure-agentic-platform-xops-and-audit

> [!NOTE]
> If you find this useful, please star the [main StackQL repo](https://github.com/stackql/stackql).

Demo assets for "Azure as data: SQL-native provisioning and agentic platform ops on Azure with StackQL". A 30 minute live demo for a Microsoft audience: the `azure` provider from the shell, `stackql-deploy` converging a service footprint across Azure and Cloudflare, then SRE, FinOps and audit agents built the Microsoft way (Copilot with the StackQL MCP server, and Microsoft Agent Framework agents on Azure OpenAI).

## synopsis

StackQL is an open source project that exposes cloud and SaaS providers as data sources accessed via SQL, supporting query, audit and provisioning operations with standard `SELECT`, `INSERT`, `UPDATE`, `DELETE` and `EXEC` semantics. The [`azure`](https://azure-provider.stackql.io/) provider covers every route in the Azure REST API (269 services, from `compute` and `network` to `cost_management`, `advisor`, `security` and `cognitive_services`) and authenticates with the same service principal variables the Azure Terraform provider uses.

This session demonstrates:

- the `azure` and `cloudflare` providers for inventory, audit (CSPM), FinOps and SRE questions from the `stackql shell` and `stackql exec`, ending in a cross-provider join (edge record -> Azure public ip -> what it is attached to)
- `stackql-deploy` as a state-file-less alternative to Bicep or Terraform: one manifest converging a resource group, network, vm, storage account, Log Analytics workspace, Azure OpenAI account and deployment, and a Cloudflare A record, with drift found and repaired
- agentic SRE, FinOps and audit with the StackQL MCP server: GitHub Copilot (VS Code agent mode or the Copilot CLI) with writes gated by human approval, plus two working Microsoft Agent Framework agents (Python and C#) whose model is the Azure OpenAI deployment the stack itself created

All tools and code shown are open source.

## layout

| Path | What it is |
| --- | --- |
| [demo/azure-provider/](demo/azure-provider/) | Demo 1: `stackql shell` and `exec` walkthroughs, plus query files with jsonnet parameters |
| [xops/](xops/) | Demo 2: the service footprint as a `stackql-deploy` stack (16 resources across `azure` and `cloudflare`), with `drift.sh` |
| [demo/agentic-use-cases/](demo/agentic-use-cases/) | Demo 3: Copilot prompts (`safe` mode), the Python FinOps agent and the C# SRE agent (`read_only` mode) |
| [.vscode/mcp.json](.vscode/mcp.json), [.github/mcp.json](.github/mcp.json) | The `stackql` MCP server for VS Code Copilot and the Copilot CLI |
| [scripts/](scripts/) | `register-providers.sh` (one-off subscription setup), `openai-env.sh` (Azure OpenAI endpoint and key into `.env`), `vm.sh` (status, start, deallocate) |

## environment

All credentials and stack variables live in the gitignored `.env` at the repo root (see `.env.example`). Source it with export semantics before running anything:

```bash
set -a; source .env; set +a
```

Variables:

```bash
# azure: a service principal with Contributor on the subscription
AZURE_TENANT_ID
AZURE_CLIENT_ID
AZURE_CLIENT_SECRET
# cloudflare: an API token with DNS edit on the zone
CLOUDFLARE_API_TOKEN
# stack variables (demo 2)
AZURE_SUBSCRIPTION_ID
AZURE_VM_SSH_PUBLIC_KEY
CLOUDFLARE_ZONE_ID
DEMO_HOST=azure-demo
DEMO_DOMAIN=stackql.xyz
# agents (demo 3), written by scripts/openai-env.sh after the first build
AZURE_OPENAI_ENDPOINT
AZURE_OPENAI_DEPLOYMENT=gpt-5-mini
AZURE_OPENAI_API_KEY
```

Prerequisites: `stackql` and `stackql-deploy` on PATH, Python 3.12, .NET 9, GitHub Copilot (VS Code extension or `@github/copilot` CLI). Pull the providers once from the repo root (stackql keeps them under `./.stackql`), and register the Azure resource providers the stack uses once per subscription (a new subscription has Compute, Network and Storage registered and little else; the script is a lifecycle `EXEC` that waits for `Registered`):

```bash
stackql exec "REGISTRY PULL azure"
stackql exec "REGISTRY PULL cloudflare"
scripts/register-providers.sh    # Microsoft.OperationalInsights, CognitiveServices, Advisor
```

## demo 1: the azure provider

- [shell.iql](demo/azure-provider/shell.iql) - `stackql shell` walkthrough: discovery, inventory, tags as rows, exposure (nsg rules that let the internet in), storage posture, FinOps waste (unattached disks, orphan public ips, a window function), Advisor, Cost Management (an `EXEC`), the Azure OpenAI deployment, the Cloudflare zone, and the two-plane join
- [exec.sh](demo/azure-provider/exec.sh) - `stackql exec` with output formats, files, jsonnet parameters and `--dryrun`

Azure resources take `subscription_id` and usually `resource_group_name` in the WHERE clause; JSON columns unpack with `JSON_EXTRACT` and `json_each`.

## demo 2: stackql-deploy

The [xops](xops/) stack: resource group, vnet, subnet, nsg, public ip, nic, vm with a custom script extension, storage account, Log Analytics workspace, two planted FinOps orphans, an Azure OpenAI account with a gpt-5-mini deployment, a Cloudflare A record, and a conformance query over both planes.

```bash
set -a; source .env; set +a

stackql-deploy build xops dev --dry-run        # show every query that would run, resolve nothing
stackql-deploy build xops dev --show-queries   # build (idempotent: re-running asserts state)
stackql-deploy test xops dev                   # exists + statecheck only, no mutations
stackql-deploy build xops prd                  # same manifest, prd values
stackql-deploy teardown xops dev               # reverse dependency order
```

The demo beat: the stack is pre-warmed, so `build` walks 16 resources in about a minute doing reads, then `xops/drift.sh` opens 22 to the internet and turns on public blob access, the SRE agent finds both, and `build` puts both back. See [xops/README.md](xops/README.md) for the resource flow and provider notes.

## demo 3: agentic use cases, the Microsoft way

- [copilot-prompts.md](demo/agentic-use-cases/copilot-prompts.md) - prompts for GitHub Copilot in VS Code (agent mode) or the Copilot CLI over the `stackql` MCP server in `safe` mode: inventory, exposure, the two-plane join, FinOps waste, Advisor, then a gated write (tag the orphan disk, deallocate the vm) approved on screen
- [python-agent](demo/agentic-use-cases/python-agent/) - FinOps analyst: Microsoft Agent Framework (Python) + Azure OpenAI + [stackql-mcp-server](https://pypi.org/project/stackql-mcp-server/) (`read_only`)
- [dotnet-agent](demo/agentic-use-cases/dotnet-agent/) - SRE assurance: Microsoft Agent Framework (.NET) + Azure OpenAI + `stackql mcp` (`read_only`)

Both agents run from the repo root and need the `AZURE_*` credentials and the `AZURE_OPENAI_*` variables from `.env` in the process environment. Their model is the deployment the stack created; `scripts/openai-env.sh` writes its endpoint and key into `.env`.

```bash
set -a; source .env; set +a
scripts/openai-env.sh dev

# python agent (FinOps analyst)
python -m venv demo/agentic-use-cases/python-agent/.venv
demo/agentic-use-cases/python-agent/.venv/Scripts/pip install -r demo/agentic-use-cases/python-agent/requirements.txt
demo/agentic-use-cases/python-agent/.venv/Scripts/python demo/agentic-use-cases/python-agent/agent.py

# .net agent (SRE assurance)
dotnet run --project demo/agentic-use-cases/dotnet-agent
```

## running order (30 minutes)

| Min | Beat | Where |
| --- | --- | --- |
| 0-3 | What StackQL is; `SHOW SERVICES IN azure`, one inventory query | shell |
| 3-8 | Exposure, storage posture, FinOps waste, Advisor; the two-plane join | shell |
| 8-13 | The manifest and one resource file; `stackql-deploy build xops dev` against the warm stack; `test` | terminal |
| 13-20 | Copilot agent mode: inventory, the join, waste, then one gated write approved on screen | VS Code |
| 20-26 | `xops/drift.sh`; the C# SRE agent finds it (about 40 s); `build` repairs it (about 1 min); the Python FinOps agent's report (about 50 s) | terminal |
| 26-30 | The shift: infrastructure as something agents query, reason about and act on; the audit log | terminal |

## pre-demo checklist

- [ ] `set -a; source .env; set +a` in every terminal you will use
- [ ] `scripts/vm.sh start dev` (deallocated between rehearsals), then `curl http://azure-demo.stackql.xyz/` returns the page
- [ ] `stackql-deploy test xops dev` is green (no drift left over from the last rehearsal; if `drift.sh` ran, `build` first)
- [ ] `scripts/openai-env.sh dev` has been run since the last build (the agents need `AZURE_OPENAI_*`)
- [ ] VS Code: Copilot Chat in agent mode shows the `stackql` tools (from `.vscode/mcp.json`); the Copilot CLI shows it with `copilot mcp list`
- [ ] `dotnet run --project demo/agentic-use-cases/dotnet-agent` and the Python agent complete against the clean stack (warm the .NET build)
- [ ] The Cost Management `EXEC` in `shell.iql` 1.11 has not been run in the last few minutes (it rate limits)

## cost

Everything in the stack is free or pay-per-use except the vm (Standard_F1als_v7, about 0.02 USD per hour), two Standard public ips (about 0.004 USD per hour each) and 34 GiB of Standard HDD disk (about 0.06 USD per day). Azure OpenAI S0 has no fixed cost; a full run of both agents on gpt-5-mini is a few cents. `scripts/vm.sh deallocate` between rehearsals keeps a week under 3 USD.

## FAQs

- __"How is this different from Bicep or the Azure Terraform provider?"__ Same REST API, same service principal, different model. Bicep and Terraform hold desired state in a DSL and actual state in a deployment or state file; StackQL holds desired state in SQL and reads actual state from the API every run. No state file, no import, and the same SQL works for ad hoc queries, CI and agents.
- __"Is the agent writing to production?"__ Only through a server mode you chose. `read_only` for the two programmatic agents; `safe` for Copilot, which routes every write through an elicitation to a human; everything is logged as JSONL with the SQL and the decision.
- __"What about secrets?"__ Credentials live in the server process environment (`--env.file .env`); the model never sees them. Sensitive stack values are marked `protected` and masked in logs.
- __"Why the Microsoft Agent Framework and not Semantic Kernel or AutoGen?"__ It is their successor and the framework Microsoft recommends for new agents; MCP tools are first class in both the Python and .NET packages, so the StackQL server plugs in with one line.

## links

- [stackql](https://github.com/stackql/stackql)
- [azure provider docs](https://azure-provider.stackql.io/)
- [cloudflare provider docs](https://cloudflare-provider.stackql.io/)
- [stackql-deploy](https://stackql-deploy.io)
- [StackQL MCP server](https://stackql.io/docs/mcp)
- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
