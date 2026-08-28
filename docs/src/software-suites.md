# Software suites

A `SoftwareSuite` describes the public performance surface of a group of
packages. Each package owns feature checks, and one package can expose their
union as a product-level suite. The same plan and result grammar drives the
Julia API, CI reports, Oxygen, Pluto, Makie and DrWatson.

## Isolation model

PerfChecker is the controller. It resolves the plan, copies the runner
environment and starts a fresh Malt worker for every measured feature/version
pair. The worker does **not** load PerfChecker, Oxygen, Pluto, Makie or DrWatson.
It loads only the selected backend, the package under test, explicitly pinned
suite dependencies and the feature file. Setup is evaluated before the timed
expression.

This keeps UI compilation and orchestration outside measurements, while
retaining the existing `@check` and dictionary APIs.

## Feature and version model

```julia
using PerfChecker

parse_feature = FeatureSpec(
    :parse_file;
    entrypoint = joinpath(@__DIR__, "features", "parse_file.jl"),
    since = v"0.1.0",
    options = Dict(:tags => [:parser, :io]),
)

parser = PackageSuite(
    "BibParser";
    environment = joinpath(@__DIR__, "runner"),
    source = dirname(@__DIR__),
    features = [parse_feature],
    release_pins = Dict(
        v"0.1.0" => ["BibInternal" => v"0.1.0"],
    ),
)

suite = SoftwareSuite(:bibliography, [parser])
plan = plan_suite(suite; profile = :ci)
result = run_suite(suite; profile = :ci)
```

`FeatureVariant`s let one feature follow API changes without pretending that
old releases expose a newer entry point. Unsupported pairs are reported as
`:unavailable`, not as regressions. `release_pins` makes historical dependency
graphs reproducible; `dev_sources` selects coherent local branches for the
current-development run.

Built-in profiles are:

- `:quick`: current local sources only;
- `:ci`: current sources plus representative compatibility boundaries;
- `:historical`: every known release selected by each package;
- `:release`: every released version, without an untagged development tree.

The quick profile does not query registries when a development source is
present. Existing release results are resolved from the cache before worker
environments are copied or Malt processes are started, so cached historical
campaigns do not create measurement workers.

Every feature script defines `perf_setup` and `perf_workload`. It is ordinary
Julia and remains independent of PerfChecker:

```julia
using BibParser

perf_setup = () -> (path = joinpath(@__DIR__, "fixture.bib"),)
perf_workload = state -> BibParser.parse_file(state.path)
```

## Common API grammar and reports

The serializable dictionaries use explicit schema identifiers:

- `perfchecker-suite-plan/1` for resolved work;
- `perfchecker-suite-job/1` for asynchronous state;
- `perfchecker-suite-result/1` for completed measurements.

`write_suite_json`, `write_suite_markdown`, `write_suite_junit` and
`write_suite_bundle` produce machine-readable output, a developer report, a CI
test report and a portable evidence bundle. Oxygen can
submit and inspect `SuiteJob`s; Pluto and Makie launch the same jobs instead of
executing timed code in their own process. DrWatson can parameterize and cache
whole suite runs.

Any suite file defining a zero-argument factory can be run without a
project-specific wrapper:

```sh
julia --project=perf path/to/PerfChecker/bin/perfchecker-suite.jl \
  --suite=perf/suite.jl --factory=build_suite --profile=ci \
  --reports=perf/results/ci
```

The repository also ships a composite GitHub Action. A consuming workflow only
needs to check out its package and any sibling development packages expected by
the suite, then invoke `JuliaConstraints/PerfChecker.jl@main` with `project`,
`suite`, `factory`, `profile`, and `reports`. It publishes the JSON, Markdown,
and JUnit reports even when a performance run fails.

## Property-generated workloads

Property-based testing is useful for discovering feature fixtures, but random
generation and shrinking must stay outside the timed expression. The stable
workflow is:

1. generate and shrink cases deterministically;
2. persist the minimal corpus and seed;
3. benchmark that fixed corpus in isolated Malt workers.

[Supposition.jl](https://github.com/Seelengrab/Supposition.jl) is the optional
bridge because it supports deterministic replay, integrated shrinking,
composable generators, stateful tests and Julia's test-set API.
[PropCheck.jl](https://seelengrab.github.io/PropCheck.jl/) remains usable as an
external corpus producer, but shipping two overlapping required integrations
would add little value. `freeze_supposition_corpus` generates a finite corpus
in the controller and stores it using the
`perfchecker-property-corpus/1` grammar. `write_property_corpus` offers the same
boundary for PropCheck or custom fuzzers. Neither generator belongs in the
measurement worker unless the feature being measured explicitly depends on it.

## Portable bundles and non-Julia providers

Every suite report now includes an atomic `perfchecker-run-bundle/1` directory:

```text
run-<id>/
  manifest.json
  measurement-definitions.json
  observations.jsonl
  diagnostics.jsonl
  artifacts.json
  artifacts/
```

The normative manifest and provider contracts are shipped in
`schemas/perfchecker-run-bundle-v1.schema.json` and
`schemas/perfchecker-provider-result-v1.schema.json`.

The adapter preserves backend-specific units and definitions. BenchmarkTools
nanoseconds are therefore never compared implicitly with Chairmarks seconds,
and `run_id`, `attempt_id`, and `reuse_key` have separate meanings. Failed and
unsupported cases are diagnostics rather than fake numeric measurements.

Other languages do not load PerfChecker. A provider runs as an ordinary child
process, receives `PERFCHECKER_OUTPUT` and `PERFCHECKER_CASE_ID`, then writes a
`perfchecker-provider-result/1` JSON document. The controller validates it and
turns it into the same bundle:

```julia
spec = ExternalCommandSpec(:python_http, "python",
    ["python", "perf/http_provider.py"];
    directory = pwd(), timeout_seconds = 120)
bundle = run_external_command(spec; bundle_root = "perf/results/external")
```

The equivalent CLI keeps shell parsing outside PerfChecker:

```sh
julia --project path/to/PerfChecker/bin/perfchecker-provider.jl \
  --id=python_http --language=python --reports=perf/results/external -- \
  python perf/http_provider.py
```

`examples/providers/python_json_provider.py` is a dependency-free executable
example that reports timing and an application payload count.

Application-level network observations use the `network.io.payload` metric and
must declare `capture_layer=application` plus an explicit `direction`. They are
semantic payload counts, not process or wire traffic. Invalid or ambiguous
network records are rejected. PerfChecker never substitutes a host-wide network
interface delta for package traffic.

Oxygen can expose a single bundle or browse a bundle directory. Store ingestion
is disabled by default and must be enabled explicitly with `allow_ingest=true`.
This lets Julia and non-Julia providers share one read model without adding
Oxygen, JSON rendering, or PerfChecker itself to measured processes.
The bundle-store route also serves a dependency-free responsive web dashboard
at its prefix root; it reads the same `/runs` resource used by other clients.

## Definition-aware comparisons

`compare_bundles` joins observations only on their exact comparison key and
measurement-definition version. Runtime-language, operating-system,
architecture, unit, definition, missing-data, and minimum-sample mismatches are
reported instead of silently converted. A comparison without a regression
policy remains diagnostic for comparable observations. Failed input runs,
missing or incompatible evidence, and insufficient samples still fail the
comparison; numeric regressions are gated only for metric namespaces that
receive an explicit relative limit:

```julia
comparison = compare_bundles(baseline, candidate;
    relative_limits = Dict(
        "julia.wall.time" => 0.05,
        "julia.alloc.bytes" => 0.02,
    ),
    min_samples = 10,
)
comparison_passed(comparison)
```

The command-line reporter writes JSON and Markdown and exits nonzero on an
invalid comparison or an explicitly gated regression:

```sh
julia --project path/to/PerfChecker/bin/perfchecker-compare.jl \
  --baseline=perf/baseline/run-... --candidate=perf/candidate/run-... \
  --limit=julia.wall.time=0.05 --min-samples=10
```

These first gates use medians and deterministic thresholds. They do not claim a
confidence level or statistical power; public noise-sensitive gates still need
the paired reliability experiments described in the architecture roadmap.

## JuliaCon 2026 extension candidates

The following announced work is relevant, but deliberately not a required
dependency yet:

- [CodeGlass](https://pretalx.com/juliacon-2026/talk/9FCTYW/) could become a
  collector for calls, conversions, dynamic dispatch, allocations and GC once
  the underlying runtime hooks stabilize;
- [TestPicker](https://pretalx.com/juliacon-2026/talk/PMRJ7G/) could provide an
  interactive selector over TestItems tags and PerfChecker feature IDs;
- [JuliaServices](https://pretalx.com/juliacon-2026/talk/MCXKBF/) suggests a
  production path around the Oxygen control plane for authentication,
  observability, durable jobs and containerized providers;
- [Julia runtime instrumentation](https://pretalx.com/juliacon-2026/talk/3AZE7E/)
  and [compilation latency work](https://pretalx.com/juliacon-2026/talk/PBYF33/)
  motivate first-class compilation/invalidations collectors.

Network throughput is also a sensible capability-gated collector for features
that actually perform network I/O. It should report protocol, direction,
payload bytes and process attribution explicitly rather than silently mixing
package traffic with environment setup or artifact downloads.
