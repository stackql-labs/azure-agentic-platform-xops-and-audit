# Demo 3: agentic platform ops with the StackQL MCP server, the Microsoft way

Two hosts, one server:

- Interactive: GitHub Copilot in VS Code (agent mode) with the `stackql` MCP server from [.vscode/mcp.json](../../.vscode/mcp.json), or the GitHub Copilot CLI with [.github/mcp.json](../../.github/mcp.json). Both launch `stackql mcp` with `--env.file .env` (credentials stay in the server process, the model never sees them) in `safe` mode: reads run, writes go through MCP elicitation and wait for a human. [.github/copilot-instructions.md](../../.github/copilot-instructions.md) gives Copilot the discovery-first rules.
- Programmatic: two Microsoft Agent Framework agents over the same server in `read_only` mode, with the model on the Azure OpenAI deployment the stack creates: [python-agent](python-agent/agent.py) (FinOps analyst, Python) and [dotnet-agent](dotnet-agent/Program.cs) (SRE assurance, C#).

The Copilot CLI only lists user-level servers (`copilot mcp list`); on the demo laptop the same server is also registered in `~/.copilot/mcp-config.json` with absolute paths. Both programmatic agents run in 35-50 seconds with 6-8 SELECTs each.

Prompts below are written to be typed live into Copilot Chat (agent mode, `stackql` tools enabled). Each one should produce visible tool calls (discovery, then SQL). Expected behaviour is in brackets. The stack is `xops` in `xops-dev-rg` (eastus2); the edge record is `azure-demo.stackql.xyz`.

## Warm-up (30 sec)

> Which stackql providers can you see, and what mode is the server in?

[calls `server_info`, `list_providers`; confirms `azure` and `cloudflare` are installed and mode is `safe`]

## Scene A - inventory and audit (the SRE on-call question)

> Inventory resource group xops-dev-rg: every resource with type, location and tags, rolled up by type.

[`list_resources` -> `describe_resource` -> `run_select_query` on `azure.resource.resources`; tabulates]

> Which network security group rules in that resource group let the internet in, on which ports?

[queries `azure.network.network_security_groups`, unpacks `security_rules` with `json_each`; names AllowHTTP on 80. If `xops/drift.sh` has run, also names AllowSSHFromInternet on 22 - the audit finding]

> Does azure-demo.stackql.xyz point at a public ip that is actually attached to something in that resource group?

[joins `cloudflare.dns.zones_dns_records` to `azure.network.public_ip_addresses` on content = ip_address, checks `ip_configuration`; two planes in one statement]

## Scene B - FinOps (the question nobody wants to answer by hand)

> What is attached to nothing in xops-dev-rg and still billing? Estimate the monthly cost.

[`azure.compute.disks` where disk_state = 'Unattached', `azure.network.public_ip_addresses` where ip_configuration is null; finds xops-dev-orphan-disk and xops-dev-orphan-pip, tagged purpose=finops-seed; puts USD figures on them]

> What does Azure Advisor recommend for this subscription, and which of those are cost recommendations?

[`azure.advisor.recommendations` by subscription_id, filters category = 'Cost']

## Scene C - act, with a human in the loop (the agentic beat)

> Tag xops-dev-orphan-disk with reviewStatus=delete-approved and a reviewedOn date of today.

[composes an `UPDATE azure.compute.disks SET tags = ...` (merging the existing tags); the server is in `safe` mode so an **elicitation prompt** appears asking for approval. Approve it on screen. The agent re-queries to confirm.]

Say out loud: the agent wrote the SQL, the server asked a human, the change is logged. Show the audit line in the MCP server log (JSONL: tool, SQL, decision, duration; never result rows).

> Deallocate xops-dev-vm, it is a demo box and nobody is using it tonight.

[`EXEC azure.compute.virtual_machines.deallocate ...`, again gated by elicitation. Decline this one to show the refusal path, or approve it and start it again with `scripts/vm.sh start` before the next scene.]

## Scene D - drift, found and repaired (if time)

Run `xops/drift.sh` (opens 22 to the internet on the NSG and turns on public blob access on the storage account), then:

> Re-run the exposure and storage posture checks on xops-dev-rg.

[finds both]

Then in a terminal: `stackql-deploy build xops dev`. The NSG is asserted (createorupdate) and the storage account patched (update anchor); re-run the prompt and both findings are gone. Desired state lives in the manifest, actual state comes from the API on every run, no state file in between.

## Fallback

If the room's network bites, run the two programmatic agents instead (`dotnet run --project demo/agentic-use-cases/dotnet-agent`, `python demo/agentic-use-cases/python-agent/agent.py`); their output is deterministic enough to narrate, and a saved run is in `demo/recordings/` once one has been captured.
