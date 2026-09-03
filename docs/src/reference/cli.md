# Command line

The unified entry point is `bin/perfchecker.jl`:

```sh
julia --project=perf path/to/PerfChecker/bin/perfchecker.jl <command> [options]
```

| Command | Purpose |
| --- | --- |
| `init` | Generate `perf/Project.toml`, a suite, and feature template. |
| `plan` | Resolve targets and print or write the immutable plan. |
| `preflight` | Resolve dependency compatibility without measuring. |
| `run` | Preflight, run the selected plan, and write reports. |
| `compare` | Compare two bundles without failing on a regression. |
| `check` | Compare two bundles and return non-zero when a limit fails. |
| `report` | Export portable JSON and Markdown from one bundle. |
| `verify` | Verify SHA-256 bundle integrity. |
| `migrate` | Rewrite a legacy bundle into a new destination. |
| `julia-campaign` | Compare one suite across Julia runtimes. |
| `network` | Measure an isolated command tree; command follows `--`. |
| `capabilities` | Emit controller/network capabilities as JSON. |
| `version` | Print PerfChecker's version. |

## Plan and run

```sh
julia --project=perf bin/perfchecker.jl plan \
  --suite=perf/suite.jl --profile=ci --output=perf/plan.json

julia --project=perf bin/perfchecker.jl preflight \
  --suite=perf/suite.jl --profile=ci \
  --output=perf/results/compatibility.json --progress=jsonl

julia --project=perf bin/perfchecker.jl run \
  --suite=perf/suite.jl --profile=ci --reports=perf/results \
  --config=perf/perfchecker-ui.json --progress=jsonl
```

Profiles are `quick`, `ci`, `historical`, and `release`. Repeat `--run-id=<id>`
to run exact plan leaves; it cannot be combined with `--config`. The default run
performs a compatibility preflight; use `--preflight=false` only when another
verified step already did so.

Each JSONL progress line starts with `PERFCHECKER_PROGRESS ` followed by a
canonical JSON object, making it safe for CI, editors, and agents to parse while
ordinary logs remain readable.

## Git targets and comparisons

`--candidate` and `--comparison` accept repeatable JSON objects. A shared UI
configuration is usually easier for humans and avoids shell quoting differences.

```sh
julia --project=perf bin/perfchecker.jl check \
  --baseline=perf/bundles/stable --candidate=perf/bundles/change \
  --limit=julia.wall.time=0.05 \
  --limit=julia.alloc.bytes=0.02 \
  --min-samples=10 --reports=perf/comparison
```

Limits are relative fractions: `0.05` means a five-percent allowed increase for
a lower-is-better metric.

## Network command

```sh
julia --project=perf bin/perfchecker.jl network \
  --provider=linux_netns --output=perf/network.json -- \
  julia --startup-file=no perf/network_workload.jl
```

On Windows, use `--provider=wsl2_netns` and optionally
`--distribution=<name>`. `--include-output=true` stores bounded stdout/stderr;
the default avoids leaking application output into reports.
