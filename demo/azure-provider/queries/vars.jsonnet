// template context for the query files in this directory
// subscription_id comes in with --var; the rest is the demo stack
{
  subscription_id: std.extVar('subscription_id'),
  resource_group: 'xops-dev-rg',
  zone: 'stackql.xyz',
}
