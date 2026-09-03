# Hosted controller and remote agents

PerfChecker can run as a long-lived Oxygen controller and delegate jobs to local
or remote agents. The controller owns plans, authorization, status, bundles, and
the browser UI. Measurement still happens in isolated workers on the machine
that accepted the job.

## Job destinations

- `local`: execute on the controller host;
- `agent:any`: lease to any compatible registered agent;
- `agent:<id>`: require one named agent.

Agents pull bounded leases and verify the immutable plan revision and selected
run IDs before execution. The server never sends arbitrary Julia expressions or
shell commands as a job payload. This keeps remote execution tied to suite code
already deployed on the agent.

```julia
using PerfChecker

run_studio_agent(
    "https://perf.example/perfchecker/v1";
    agent_id = "linux-amd64-01",
    token = ENV["PERFCHECKER_AGENT_TOKEN"],
)
```

## Authentication and authorization

The built-in TOML token store is appropriate for a controlled deployment and
stores token digests, roles, and optional agent restrictions. `admin`, `runner`,
and `agent` roles separate UI administration, job creation, and agent leasing.
Install a custom authenticator/authorizer when identity must come from an
existing organization service.

For any non-loopback deployment:

1. require `allow_remote_control=true` explicitly;
2. provide an authenticator;
3. terminate TLS at Oxygen or a hardened reverse proxy;
4. rotate and scope tokens, and keep them out of repositories and logs;
5. isolate controller/agent service accounts and writable directories;
6. set retention, backup, and redaction policies for bundles and artifacts;
7. restrict which suite revisions are deployed to agents.

HttpOnly session cookies and CSRF checks protect browser actions, but they do not
replace network policy, TLS, secret management, operating-system isolation, or
audit retention.

## Capability matching

Before dispatch, match jobs against the agent's runtime, platform, Julia version,
collector packages, network-isolation provider, privileges, and relevant native
tools. An agent that can launch a command is not automatically qualified to
produce comparable evidence. Persist the capability snapshot with each run.

## Progress and recovery

The same progress model drives Oxygen, VS Code, REPL, Pluto, CLI JSONL, and
agents. Jobs expose queued, leased, running, complete, failed, and cancelled
states. Consumers should use stable job/run IDs, tolerate reconnects, and verify
the final run bundle before accepting it into CI or documentation.
