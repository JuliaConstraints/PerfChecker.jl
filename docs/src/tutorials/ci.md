# CI/CD

CI should replay the same suite used locally, preserve all evidence, and fail
only on explicit policy. PerfChecker ships a composite GitHub Action plus a
provider-neutral CLI for other CI systems.

## GitHub Actions

```yaml
name: Performance

on:
  pull_request:
  push:
    branches: [main]

jobs:
  perf:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Mirage-Interactive-Fr/PerfChecker.jl@main
        with:
          julia-version: "1"
          project: perf
          suite: perf/suite.jl
          profile: ci
          reports: perf/results/ci
```

The action installs the controller, runs with JSONL progress, and uploads the
report directory even when a performance check fails.

Pin a release tag or commit rather than `main` once V1 is published.

## Any CI system

```sh
julia --startup-file=no --project=perf \
  /path/to/PerfChecker.jl/bin/perfchecker.jl run \
  --suite=perf/suite.jl \
  --profile=ci \
  --config=perf/perfchecker-ui.json \
  --reports=perf/results/ci \
  --progress=jsonl
```

Exit code `0` means the selected suite passed. Compatibility failure, unavailable
required runs, workload errors and violated comparison policies produce a
non-zero exit.

## Compare two stored bundles

```sh
perfchecker check \
  --baseline=perf/baseline/run-abc \
  --candidate=perf/candidate/run-def \
  --limit=julia.wall.time=0.05 \
  --limit=julia.alloc.bytes=0.02 \
  --min-samples=10 \
  --reports=perf/comparison
```

`compare` writes the same report without turning regression status into a failing
exit code. Use `check` for a gate.

## Noise-control checklist

- Use dedicated or stable runners for strict latency budgets.
- Keep CPU governor, power mode, thread count and affinity comparable.
- Avoid unrelated network and disk activity.
- Record warm-up policy and separate startup/compilation from steady state.
- Compare distributions with enough samples; do not gate on a single timing.
- Keep fixtures and `comparison_key` stable.
- Treat cross-machine results as informative unless normalization is explicitly
  part of the policy.

## Artifacts to retain

At minimum retain `suite-result.json`, `suite-junit.xml`, `version-series.json`,
`version-comparison.json`, `compatibility.json`, and the `bundles/` tree. Profile
exports, screenshots and Markdown are projections that can be regenerated from
the bundle when their underlying evidence is present.
