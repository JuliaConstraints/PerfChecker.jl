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

task_profile = FeatureSpec(
    :parse_file_wall_profile;
    workload = :parse_file,
    backend = :wall_profile,
    entrypoint = joinpath(@__DIR__, "features", "parse_file.jl"),
    since = v"0.1.0",
    julia_since = v"1.12",
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

`FeatureSpec.id` identifies the concrete check, while `FeatureSpec.workload`
identifies the business feature across collectors. Thus a suite can retain
stable internal IDs such as `parse_file_wall_profile`, while every interface
groups it under `parse_file` and lets the user choose wall-time profiling as an
evaluation option.

Named Git alternatives are first-class targets:

```julia
candidate = SuiteCandidate("fast-parser", "feature/fast-parser";
    source = "https://github.com/acme/Parser.jl",
    compatibility_version = v"2.1")
parser = PackageSuite("Parser"; environment, source, features,
    candidates = [candidate])
policy = ComparisonPolicy("parse-candidates";
    package = "Parser", comparison_key = "parse/v1",
    baselines = ["2.0.0", "2.1.0"],
    candidates = ["fast-parser"], aggregation = :median)
suite = SoftwareSuite(:parser, [parser]; comparisons = [policy])
```

One baseline label is an exact comparison; several labels build an explicitly
aggregated reference group. Multiple candidate labels can be evaluated in the
same campaign. VS Code writes the same targets and policies into
`perfchecker-ui-config/1`, and the CLI replays them with `--config`.

Package and Julia compatibility are independent axes. `since`, `until` and
`excluded` constrain package releases; `julia_since`, `julia_until` and
`julia_excluded` constrain the runtime executing that feature. The resolved
`perfchecker-suite-plan/1` includes both the selected package target and the
Julia window, so every interface explains a skipped pair consistently.

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
the suite, then invoke `Mirage-Interactive-Fr/PerfChecker.jl@main` with `project`,
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
[PropCheck.jl](https://seelengrab.github.io/PropCheck.jl/) is in maintenance
mode, but remains supported by an optional compatibility extension for existing
suites. `freeze_supposition_corpus` and `freeze_propcheck_corpus` generate a finite corpus
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
  integrity.json
  artifacts/
```

New bundles contain a SHA-256 integrity manifest covering every protocol
document. `read_run_bundle` verifies it before parsing. Older `/1` bundles
without this manifest remain readable as `legacy_unverified`; hosted ingestion
or CI can require verification with
`verify_run_bundle(path; require_integrity=true)`. `migrate_run_bundle` rewrites
an older bundle atomically into a digest-protected destination without changing
the source.

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

`write_suite_reports` additionally writes `version-series.json`,
`version-comparison.json`, and `version-comparison.md`. Series are grouped by
package, business workload, concrete check, comparison key, metric, definition,
and unit. PerfChecker
compares adjacent compatible releases and then the development checkout against
the latest compatible release. The plan is embedded in the bundle, so an
unavailable, failed, or unexpectedly missing target is visible and cannot be
silently bridged by a comparison.

## Oxygen Performance Studio

Registering a `SoftwareSuite` serves a dynamic Studio at the route prefix. It
generates the authoritative plan and starts a bounded queue. Developers select
whole inclusive version intervals, combine package, feature, backend and text
filters, sort by semantic version/package/feature, and add, remove or invert
every visible run in one action. Deterministic colour labels make packages and
versions identifiable across large matrices. Checkboxes, keyboard controls and
drag-and-drop remain available for individual runs.

The same selection grammar is available without a browser:

```julia
plan = plan_suite(suite; profile = :historical)
selected = filter_suite_plan(plan;
    packages = ["Parser"], backends = [:benchmark, :profile_alloc],
    from_version = v"1.2", to_version = v"2.0", sort = :version_package)
result = run_suite_repl(selected; reports = "perf/results/custom")
```

`configure_suite_repl` provides guided package, feature, backend, inclusive
version-range, search, ordering, samples, duration, and thread choices.
`run_suite_repl` renders the common run-count progress contract. Loading
UnicodePlots adds terminal-native charts. Suite jobs expose the same progress
as JSON, including the current run, so Oxygen, remote agents, Pluto, and
non-Julia clients can render a consistent progress bar.

Loading Documenter adds `documenter_page` and `documenter_makedocs`. Loading
DocumenterVitepress adds `documenter_vitepress_makedocs`; both consume stored
bundles and remain outside measured workers.

```julia
using Oxygen, PerfChecker

serve_suite(suite; profile = :ci, reports_root = "perf/results/studio")
```

Each selected run still starts a fresh Malt worker. Oxygen, PerfChecker, and UI
libraries stay in the controller. A job becomes `complete` only after its bundle
and comparison reports have been written atomically. Jobs, sessions and agent
registrations are written atomically to `studio-state.json`; interrupted local
jobs are requeued after restart. Remote work uses expiring hashed lease tokens,
heartbeats and bounded retries. Queued or running jobs can be cancelled.

### Makie plot grammar

Every stored bundle exposes a backend-neutral `perfchecker-plot/1` description.
`plot_catalog(bundle)` lists the available views and `performance_plot(bundle, id)`
returns their data and encodings. This is the common contract used by the Julia
API, Oxygen JSON routes, Pluto notebooks, and Makie renderers.

Loading Makie adds `performance_figure`. The active Makie backend controls the
surface without changing the plot definition:

- WGLMakie renders interactive WebGL figures inside the Oxygen Studio;
- GLMakie provides the local GPU window for package developers;
- CairoMakie writes deterministic PNG, SVG, or PDF artifacts in CI.

The catalog includes per-version trajectories, raw-sample distributions,
adjacent-version deltas, time/allocation trade-offs, allocations stacked by
source file, top allocation sites by `file:line`, and a version-by-line
allocation heatmap. A percentage pie shows the allocation share per file.
`Profile` CPU samples, Julia 1.12 task wall-time samples, and `Profile.Allocs`
allocation stacks also produce version-selectable Makie flame graphs. Folded
stacks and Speedscope JSON are portable core exports; loading PProf and
FlameGraphs adds compressed pprof protobuf output. These profile views come from the
isolated workload worker and never profile the controller or dashboard process.

Every flame rectangle is inspectable, including sections too narrow to carry a
visible label. Hovering reports the complete call path, weight, percentage and
available Julia diagnostics. The legend uses red for observed runtime dispatch,
purple for a cached non-concrete inferred return, and orange for garbage
collection. Runtime dispatch and a multi-type return are deliberately separate:
the latter is evidence to inspect with `@code_warntype` or Cthulhu, not by itself
proof of a performance defect. Allocation flame graphs retain the same full-path
hover but do not claim CPU type-inference diagnostics. GLMakie and CairoMakie use
the Makie figure directly; the self-contained web export uses an SVG interaction
layer so hover and keyboard focus remain functional without a live Julia callback.

The corresponding Oxygen routes are `GET /plots`, `GET /plot-data`, and
`GET /plot`. The last route is available when WGLMakie is loaded by the
controller.

For a hosted controller, `serve_suite` refuses a non-loopback host unless both
`allow_remote_control=true` and an `authenticator` are supplied. The included
`studio_token_authenticator` maps SHA-256 token digests to user identities. A
custom bearer/OIDC validator and `authorizer` callback can integrate an existing
identity system. A built-in TOML user store accepts `[[users]]` records with
SHA-256 token digests, roles, and optional allowed agent IDs. Browser sessions
use HttpOnly cookies and CSRF tokens. The default roles are `admin`, `runner`,
and `agent`; TLS and token issuance remain deployment responsibilities.

Jobs may target `local`, `agent:any`, or `agent:<id>`. A pull-based agent calls
`run_studio_agent`, verifies that its locally generated suite-plan revision and
run IDs match the server lease, executes through the normal isolated runner,
and uploads the portable bundle. The server never transmits source expressions
or shell commands to the agent.

## Network and experiment integrations

The `:network` backend measures only counters explicitly returned by the
workload (`bytes_sent`, `bytes_received`, and/or `operations`). It produces
payload throughput and operation rate without confusing package traffic with
registry downloads or host-wide interface noise. It is appropriate for HTTP,
database and distributed features; suites without network semantics should not
enable it.

The `:network_interface` backend records operating-system byte, packet and drop
deltas, but labels them `host_interface`; they are not package-attributable on a
shared machine. The `:network_isolated` backend is the blocking-CI variant. It
requires the suite controller and its Malt workers to be launched by
`measure_isolated_network_command`, then records the dedicated namespace
counters around each feature workload. See [Network measurement](network-measurement.md)
for native Linux and WSL2 setup.

`drwatson_run_suite` caches a complete suite result through DrWatson and writes
the normal report tree. `prepare_pluto_dashboard` prepares a suite job or loads
an existing bundle for a notebook without profiling Pluto. Both remain
controller-side integrations.

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
