# PerfChecker.jl

PerfChecker runs performance checks for Julia packages in isolated Julia
processes. The public entry point is `@check`; new code should prefer
`PerfConfig`, while the older dictionary form remains supported.

Version `1.0.0-rc2` adds the feature-suite workflow, a unified CLI, immutable
run bundles with integrity metadata, compatibility preflight, Julia runtime
campaigns, attributed network accounting, and shared report/query contracts.
See [V1 candidate](v1-candidate.md) for the supported surface and migration
rules.

```julia
using PerfChecker, BenchmarkTools

config = PerfConfig(
    :benchmark;
    path = @__DIR__,
    tags = [:smoke],
    samples = 10,
    evals = 1,
)

result = @check config begin
    x = collect(1:100)
end begin
    sum(x)
end
```

The `Dict` interface is intentionally kept for compatibility, but both public
forms are normalized internally before running. Missing required options such as
`:path`, invalid tags, invalid thread counts, and malformed package-version
selectors fail before workers are launched.

## Multi-version Checks

```julia
config = PerfConfig(
    :benchmark;
    path = @__DIR__,
    tags = [:release_comparison],
    pkgs = ("Example", :custom, [v"1.0.0", v"1.1.0"], true),
)
```

The `:pkgs` tuple is `(name, selector, versions, prefer_latest)`. Supported
selectors are `:custom`, `:patches`, `:minor`, `:major`, and `:breaking`.

## Local Development Branches

Use `:devops` to compare a local branch with released versions. PerfChecker
removes the target package from the copied environment before `Pkg.add` or
`Pkg.develop`, which avoids stale UUID/source state from previous runs.

```julia
config = PerfConfig(
    :benchmark;
    path = @__DIR__,
    pkgs = ("Example", :custom, [v"1.0.0"], true),
    devops = "Example",
)
```

## REPL and Pluto Setup

Generate a small Julia-native performance workspace with:

```julia
perf_setup()
```

The generated Pluto dashboard activates the surrounding Julia project and
starts with `run_check = false`, so opening it in Pluto does not immediately
launch performance workers.

## CI

Run tests with startup files disabled so user-level packages do not mutate the
test environment:

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
```

For feature-level, multi-version and multi-package checks, see
[Software suites](software-suites.md). A suite keeps PerfChecker and its user
interfaces in the controller process: isolated Malt workers load only the
benchmark backend, the package under test and its explicitly pinned peers.

PerfChecker also ships `action.yml` and `bin/perfchecker.jl` so the same
suite factory and report grammar can be used in GitHub Actions or another CI
without duplicating orchestration code.

```@autodocs
Modules=[PerfChecker]
```
