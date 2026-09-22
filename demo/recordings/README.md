# recordings

Saved runs of the two programmatic agents (demo 3) against the live `xops` dev stack on 22 Sep 2026, for narrating over if the room's network fails:

- [sre-agent-clean-stack.txt](sre-agent-clean-stack.txt) - the C# SRE assurance sweep on the converged stack (7 SELECTs, about 40 s)
- [sre-agent-drifted-stack.txt](sre-agent-drifted-stack.txt) - the same sweep after `xops/drift.sh` (finds the rule open to the internet on 22 and the public blob access)
- [finops-agent.txt](finops-agent.txt) - the Python FinOps analyst (7 SELECTs, about 50 s; prices the two planted orphans)

Each line starting with `->` is a tool call as the agent made it; the SQL is the audit trail.
