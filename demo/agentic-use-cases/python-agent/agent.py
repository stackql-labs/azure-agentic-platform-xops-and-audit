"""FinOps analyst agent for the Azure subscription.

Microsoft Agent Framework (agent-framework-core + agent-framework-openai) with
the model on Azure OpenAI (the gpt-5-mini deployment the xops stack creates)
and the StackQL MCP server (stackql-mcp-server from PyPI, which downloads the
signed stackql binary on first run) as the tool surface. The server runs in
read_only mode: the agent can query the estate but cannot mutate it,
regardless of the prompt. Every tool call is a readable SQL statement, printed
as it happens by a function middleware, and logged by the server as JSONL.

Setup (from the repo root):
    python -m venv demo/agentic-use-cases/python-agent/.venv
    demo/agentic-use-cases/python-agent/.venv/Scripts/pip install -r demo/agentic-use-cases/python-agent/requirements.txt
    set -a; source .env; set +a      # AZURE_* (stackql auth), AZURE_OPENAI_* (model)
    python demo/agentic-use-cases/python-agent/agent.py
"""

import asyncio
import json
import os
import shutil
import sys
from datetime import date
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from agent_framework import Agent, FunctionInvocationContext, MCPStdioTool, function_middleware
from agent_framework.openai import OpenAIChatClient

REPO_ROOT = Path(__file__).resolve().parents[3]
STACK_ENV = os.environ.get("STACK_ENV", "dev")

INSTRUCTIONS = """You are a FinOps analyst for our Azure subscription {subscription_id}.
You have the stackql tools: cloud and SaaS providers as data sources accessed
via SQL. Resources are named provider.service.resource; the ones you need are
named in the task with their columns, so go straight to run_select_query and
only use describe_resource (with row_limit 5) if a query fails.
Rules for SQL: the first token of every query is SELECT (no leading comments,
the read_only guard rejects them); the dialect is SQLite (LIMIT, not TOP);
Azure resources take subscription_id and usually resource_group_name in the
WHERE clause; JSON columns are unpacked with JSON_EXTRACT; booleans compare
as 0/1; numeric columns arrive as text. An empty result is zero rows, not an
error. Run at least one query per numbered item and quote the values the
query returned as evidence; never report on an item you did not query. Keep
answers short and factual, with figures in USD list price."""

PROMPT = """Today is {today}. The service under review is in resource group
{resource_group} (region eastus2, tags stackName=xops, stackEnv={stack_env}).

1. Estate: azure.resource.resources (columns name, type, tags) for the
   resource group, rolled up by type.
2. Waste: azure.compute.disks (name, disk_state, disk_size_gb, sku, tags)
   where disk_state = 'Unattached', and azure.network.public_ip_addresses
   (name, ip_address, sku, ip_configuration, tags) where ip_configuration IS
   NULL. Estimate the monthly list cost of each (Standard public ip about
   3.65 USD, Standard HDD managed disk about 0.05 USD per GiB).
3. Compute: azure.compute.virtual_machines (name, hardware_profile,
   provisioning_state, storage_profile): size, state and os disk type. Say
   whether the size is the smallest reasonable for a demo web server.
4. Advisor: azure.advisor.recommendations for the subscription (category,
   impact, short_description, impacted_field). Call out the Cost category.
5. Spend: azure.consumption.usage_details with scope =
   '/subscriptions/{subscription_id}' if any rows exist; if empty, say so in
   one line and move on.

Finish with a plain-text report: an estate table by type, a waste table with
monthly USD, one line per recommendation, a total monthly waste figure, and
two actions ranked by saving."""


@function_middleware
async def print_tool_calls(context: FunctionInvocationContext, call_next) -> None:
    """Every tool call, as it happens: the tool and its arguments (the SQL)."""
    args = context.arguments
    text = args if isinstance(args, str) else json.dumps(args, default=str)
    print(f"  -> {context.function.name} {text[:200]}", flush=True)
    await call_next()


def stackql_mcp() -> MCPStdioTool:
    """The StackQL MCP server as an agent tool: the console script if it is on
    PATH, otherwise the one in this interpreter's Scripts directory. The app
    root (where REGISTRY PULL put the providers) is the repo root."""
    cmd = shutil.which("stackql-mcp-server") or str(Path(sys.executable).with_name("stackql-mcp-server"))
    return MCPStdioTool(
        name="stackql",
        command=cmd,
        load_prompts=False,  # the 16 server tools only, not the server's prompts
        args=[
            "--mcp.server.type=stdio",
            "--approot", str(REPO_ROOT / ".stackql"),
            "--mcp.config", '{"server": {"transport": "stdio", "mode": "read_only"}}',
        ],
        env=dict(os.environ),
    )


def model_client() -> OpenAIChatClient:
    """Azure OpenAI when AZURE_OPENAI_ENDPOINT is set (the stack's deployment),
    otherwise OpenAI with OPENAI_API_KEY. Model ids come from the environment."""
    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
    if endpoint:
        return OpenAIChatClient(
            model=os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-5-mini"),
            azure_endpoint=endpoint,
            api_key=os.environ["AZURE_OPENAI_API_KEY"],
        )
    return OpenAIChatClient(
        model=os.environ.get("OPENAI_MODEL", "gpt-5-mini"),
        api_key=os.environ["OPENAI_API_KEY"],
    )


async def main() -> None:
    subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID", "<unset>")
    resource_group = f"xops-{STACK_ENV}-rg"
    calls = {"n": 0}

    @function_middleware
    async def count_calls(context: FunctionInvocationContext, call_next) -> None:
        calls["n"] += 1
        await call_next()

    async with stackql_mcp() as stackql:
        print(f"connected: {len(stackql.functions)} stackql tools (read_only)\n")
        agent = Agent(
            client=model_client(),
            name="azure-finops-agent",
            instructions=INSTRUCTIONS.format(subscription_id=subscription_id),
            tools=[stackql],
            middleware=[print_tool_calls, count_calls],
            default_options={"reasoning": {"effort": "low"}},
        )
        prompt = PROMPT.format(
            today=date.today(),
            subscription_id=subscription_id,
            resource_group=resource_group,
            stack_env=STACK_ENV,
        )
        print("=== FinOps sweep ===\n")
        response = await agent.run(prompt)
        print("\n=== FinOps report ===\n")
        print(response.text)
        print(f"\n=== {calls['n']} tool calls, all SELECTs, all logged by the server ===")


if __name__ == "__main__":
    asyncio.run(main())
