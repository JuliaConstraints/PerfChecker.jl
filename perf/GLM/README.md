# GLM.jl legacy example

This directory contains the original allocation and benchmark scripts for
GLM.jl. They remain available to preserve the pre-suite PerfChecker examples,
but new integrations should use a feature-oriented software suite instead.

Start with the [first-check guide](../../docs/src/guide/first-check.md), define
each GLM operation as a `FeatureSpec`, and select benchmarking, allocation, or
profiling backends independently. PerfChecker then resolves package versions and
development revisions in isolated workers; manually switching the GLM checkout
is no longer required.

The historical scripts can still be run from this environment:

```sh
julia --project=perf/GLM perf/GLM/allocs.jl
julia --project=perf/GLM perf/GLM/bench.jl
```

Their CSV files and figures are legacy outputs. Portable run bundles and the
current VS Code, Oxygen, Makie, Pluto, REPL, and documentation interfaces are
described in the main documentation.
