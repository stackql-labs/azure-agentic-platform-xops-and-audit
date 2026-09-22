// SRE assurance agent for the xops service footprint (Azure compute, edge on Cloudflare).
//
// Microsoft Agent Framework (.NET) with the model on Azure OpenAI (the gpt-5-mini
// deployment the xops stack creates) and the StackQL MCP server as the tool
// surface. The server runs in read_only mode: the agent can query the estate but
// cannot mutate it, regardless of the prompt. Every tool call is a readable SQL
// statement, printed as it happens, and logged by the server as JSONL.
//
// Setup (from the repo root):
//   set -a; source .env; set +a      # AZURE_* (stackql auth), AZURE_OPENAI_* (model)
//   dotnet run --project demo/agentic-use-cases/dotnet-agent

using System.ClientModel;
using System.Text.Json;
using Azure.AI.OpenAI;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;
using OpenAI;
using OpenAI.Chat;

var endpoint = Require("AZURE_OPENAI_ENDPOINT");
var apiKey = Require("AZURE_OPENAI_API_KEY");
var deployment = Environment.GetEnvironmentVariable("AZURE_OPENAI_DEPLOYMENT") ?? "gpt-5-mini";
var subscriptionId = Environment.GetEnvironmentVariable("AZURE_SUBSCRIPTION_ID") ?? "<unset>";
var zoneId = Environment.GetEnvironmentVariable("CLOUDFLARE_ZONE_ID") ?? "<unset>";
var host = Environment.GetEnvironmentVariable("DEMO_HOST") ?? "azure-demo";
var domain = Environment.GetEnvironmentVariable("DEMO_DOMAIN") ?? "stackql.xyz";
var stackEnv = Environment.GetEnvironmentVariable("STACK_ENV") ?? "dev";
var resourceGroup = $"xops-{stackEnv}-rg";

// The stackql app root (providers pulled with REGISTRY PULL) lives at the repo
// root, whatever directory the agent is launched from.
var repoRoot = FindRepoRoot();

var transport = new StdioClientTransport(new StdioClientTransportOptions
{
    Name = "stackql",
    Command = "stackql",
    Arguments =
    [
        "mcp",
        "--mcp.server.type=stdio",
        "--approot", Path.Combine(repoRoot, ".stackql"),
        "--mcp.config", "{\"server\": {\"transport\": \"stdio\", \"mode\": \"read_only\"}}",
    ],
});

await using var mcp = await McpClient.CreateAsync(transport);
var tools = await mcp.ListToolsAsync();
Console.WriteLine($"connected: {tools.Count} stackql tools (read_only)\n");

var instructions = $"""
You are the on-call SRE for the service {host}.{domain}: compute on Azure
(subscription {subscriptionId}, resource group {resourceGroup}, region eastus2)
with its edge on Cloudflare (zone {domain}, zone id {zoneId}).
You have the stackql tools: cloud and SaaS providers as data sources accessed
via SQL. Resources are named provider.service.resource; the ones you need are
named in the task with their columns, so go straight to run_select_query and
only use describe_resource (with row_limit 5) if a query fails.
Rules for SQL: the first token of every query is SELECT (no leading comments,
the read_only guard rejects them); Azure resources take subscription_id and
usually resource_group_name in the WHERE clause; Cloudflare DNS records take
zone_id; the dialect is SQLite (LIMIT, not TOP); JSON columns are unpacked
with JSON_EXTRACT; booleans compare as 0/1; numeric columns arrive as text.
An empty result is zero rows, not an error. Run at least one query per
numbered check and quote the values the query returned as evidence; never
report a check you did not query. Keep each answer short and factual.
""";

var prompt = $"""
Run the morning assurance sweep for {host}.{domain}.

1. Compute health: azure.compute.virtual_machines (name, hardware_profile,
   provisioning_state) in the resource group. Flag anything not Succeeded.
2. Exposure: azure.network.security_rules (name, access, direction, priority,
   destination_port_range, source_address_prefix; takes
   network_security_group_name = 'xops-{stackEnv}-nsg'): list every inbound
   Allow rule whose source is '*', '0.0.0.0/0' or 'Internet' with its port and
   priority. Port 80 from anywhere is expected (PASS); any other port open to
   the internet is a finding (ATTENTION).
3. Storage posture: azure.storage.storage_accounts (name,
   allow_blob_public_access, minimum_tls_version, supports_https_traffic_only)
   in the resource group. Flag public blob access or TLS below 1.2.
4. Edge to origin: cloudflare.dns.zones_dns_records (name, type, content;
   takes zone_id) for {host}.{domain}, and azure.network.public_ip_addresses
   (name, ip_address, ip_configuration) in the resource group. The record must
   point at an ip whose ip_configuration is not null.
5. Governance: azure.resource.resources (name, type, tags) in the resource
   group missing an owner or costCentre tag (JSON_EXTRACT on tags).
6. Advisor: azure.advisor.recommendations (category, impact,
   short_description) for the subscription (WHERE subscription_id = ...);
   report every High impact recommendation by its short_description.

Finish with a plain-text report: PASS or ATTENTION per check, with one line
of evidence each, then one line on total tool calls made.
""";

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new ApiKeyCredential(apiKey))
    .GetChatClient(deployment)
    .AsAIAgent(new ChatClientAgentOptions
    {
        Name = "azure-sre-agent",
        ChatOptions = new ChatOptions
        {
            Instructions = instructions,
            Tools = [.. tools],
            Reasoning = new ReasoningOptions { Effort = ReasoningEffort.Low },
        },
    });

var toolCalls = 0;
Console.WriteLine("=== sweep ===\n");
await foreach (var update in agent.RunStreamingAsync(prompt))
{
    foreach (var content in update.Contents)
    {
        switch (content)
        {
            case FunctionCallContent call:
                toolCalls++;
                var callArgs = call.Arguments is null ? "" : JsonSerializer.Serialize(call.Arguments);
                Console.WriteLine($"  -> {call.Name} {Truncate(callArgs, 160)}");
                break;
            case TextContent text:
                Console.Write(text.Text);
                break;
        }
    }
}
Console.WriteLine($"\n\n=== {toolCalls} tool calls, all SELECTs, all logged by the server ===");

static string Require(string name) =>
    Environment.GetEnvironmentVariable(name)
    ?? throw new InvalidOperationException($"{name} is not set (source .env, see scripts/openai-env.sh)");

static string Truncate(string s, int n) => s.Length <= n ? s : s[..n] + "...";

static string FindRepoRoot()
{
    var dir = new DirectoryInfo(AppContext.BaseDirectory);
    while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "xops", "stackql_manifest.yml")))
    {
        dir = dir.Parent;
    }
    return dir?.FullName ?? Directory.GetCurrentDirectory();
}
