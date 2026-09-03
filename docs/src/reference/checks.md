# Check catalog

PerfChecker attaches one or more **check types** to a business feature. A feature
such as `import_bibtex` stays one feature whether you measure latency,
allocations, CPU samples, or network traffic. The backend only changes the
evidence collected by its isolated worker.

## Implemented backends

| Backend | Primary evidence | Important options | Notes |
| --- | --- | --- | --- |
| `:benchmark` | BenchmarkTools time distribution, GC time, bytes and allocation count | `samples`, `seconds`, `evals`, `overhead`, `gctrial`, `gcsample` | Best default for steady-state latency and allocations. Requires BenchmarkTools. |
| `:chairmark` | Chairmarks sample distribution and memory statistics | backend-specific Chairmarks options | Low-overhead alternative for short measurements. Requires Chairmarks. |
| `:alloc` | Allocation bytes attributed to source file and line | `threads`, `targets`, `track`, `repeat` | Uses Julia allocation tracking; select source targets deliberately. |
| `:profile` | CPU samples, stack frames, dispatch/GC markers and inferred return status | `profile_seconds`, `profile_delay`, `buffer`, `max_stack_depth`, `max_profile_stacks` | Sampled evidence, suitable for flame graphs and attribution. |
| `:wall_profile` | Task wall-time samples | profile duration/delay and stack limits | Requires a Julia runtime with wall-time profiling support. |
| `:profile_alloc` | Sampled allocation bytes/counts and allocation stacks | `sample_rate`, `profile_repetitions`, stack limits | Uses `Profile.Allocs`; useful for type and stack drill-down. |
| `:network` | Workload-reported payload bytes, operations and optional packet/connection counters | repetitions and workload contract | Strong attribution to the feature, but only for counters the workload reports. |
| `:network_interface` | Host-interface bytes, packets and drops | interface selector | Includes unrelated host traffic unless the interface is controlled. |
| `:network_isolated` | Network-namespace bytes, packets and drops | `NetworkIsolationSpec` | Strong process-group attribution on Linux or WSL2. |

Optional integrations load through Julia package extensions. A normal
PerfChecker installation therefore does not load Makie, Oxygen, Pluto,
BenchmarkTools, or Chairmarks until the corresponding package is present in the
controller or measurement environment.

## One feature, several checks

The suite can expose several `FeatureSpec` entries with the same `workload`
identifier and different backends. Every interface groups those entries under
the business feature and lets the user select the check types independently.

```julia
checks = [
    FeatureSpec(:import_bibtex_time;
        workload = :import_bibtex,
        backend = :benchmark,
        entrypoint = joinpath(@__DIR__, "features", "import_bibtex.jl")),
    FeatureSpec(:import_bibtex_allocations;
        workload = :import_bibtex,
        backend = :profile_alloc,
        entrypoint = joinpath(@__DIR__, "features", "import_bibtex.jl")),
    FeatureSpec(:import_bibtex_cpu;
        workload = :import_bibtex,
        backend = :profile,
        entrypoint = joinpath(@__DIR__, "features", "import_bibtex.jl")),
]
```

The entrypoint is ordinary Julia code and should return the same semantic result
for every target. Keep fixture construction outside the measured expression
when setup cost is not part of the contract.

## Choosing evidence

- Use `:benchmark` or `:chairmark` to decide **whether** a regression exists.
- Use `:profile`, `:wall_profile`, `:profile_alloc`, and `:alloc` to investigate
  **where** the cost moved.
- Use `:network` for exact application counters and `:network_isolated` for
  attributed process-tree traffic.
- Treat host-interface latency and traffic as contextual unless the host is
  hermetic.
- Never compare values whose measurement-definition IDs or comparison keys are
  incompatible.

See the [measurement model](../measurement-model.md) for lifecycle phases and
scope, and [interactive plots](../interfaces/visualization.md) for the views
generated from these observations.
