#!/usr/bin/env bash
# The stack's vm is the only thing in xops that bills by the hour. Deallocate
# it between rehearsals, start it before the demo. Run from the repo root.
#   scripts/vm.sh status|start|deallocate|restart [dev|prd]
set -euo pipefail
cmd=${1:-status}
env=${2:-dev}
set -a; . ./.env; set +a
rg="xops-${env}-rg"
vm="xops-${env}-vm"
case "$cmd" in
  start|deallocate|restart)
    stackql exec "EXEC azure.compute.virtual_machines.${cmd}
      @vm_name = '${vm}', @resource_group_name = '${rg}', @subscription_id = '${AZURE_SUBSCRIPTION_ID}'"
    ;;
  status)
    # the instance view is a get with \$expand; the power state is the second status
    stackql exec "SELECT name, provisioning_state,
      JSON_EXTRACT(instance_view, '\$.statuses[1].displayStatus') AS power_state
      FROM azure.compute.virtual_machines
      WHERE subscription_id = '${AZURE_SUBSCRIPTION_ID}' AND resource_group_name = '${rg}'
      AND vm_name = '${vm}' AND \$expand = 'instanceView'"
    ;;
  *)
    echo "usage: scripts/vm.sh status|start|deallocate|restart [dev|prd]" >&2
    exit 2
    ;;
esac
