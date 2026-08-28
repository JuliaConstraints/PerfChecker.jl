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

`write_suite_json`, `write_suite_markdown` and `write_suite_junit` produce
machine-readable output, a developer report and a CI test report. Oxygen can
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
