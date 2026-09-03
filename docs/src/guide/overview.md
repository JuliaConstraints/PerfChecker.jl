# Overview

PerfChecker answers four different questions that are often mixed together:

1. **What is being measured?** A stable business feature and a representative workload.
2. **How is it measured?** A benchmark, allocation tracker, profiler, network collector, or provider.
3. **Which implementation is measured?** A release, working tree, branch, tag, commit, or Julia runtime.
4. **How is evidence consumed?** A CI gate, interactive plot, report, documentation block, human review, or agent workflow.

Keeping these axes independent is the central design rule. A feature such as
`import_bibtex` should not be duplicated into names such as
`import_bibtex_allocations` and `import_bibtex_profile` in the user interface.
Those are check types attached to one feature.

## Execution model

PerfChecker has a controller/worker boundary:

| Component | Responsibilities | Included in measurements? |
|---|---|---:|
| Controller | Resolve versions, build plans, schedule jobs, write reports, serve UIs | No |
| Malt worker | Load one target, one workload and one collector | Yes |
| Reporter | Convert bundles into tables, plots, documentation and CI evidence | No |
| Oxygen agent | Lease work from a controller and launch local isolated workers | No |

A worker is fresh for every planned feature/target pair. Startup and compilation
can be measured deliberately, but controller compilation, Makie, Oxygen, Pluto
and VS Code never leak into the timed workload by accident.

## Two public workflows

### Direct `@check`

`@check` is the compact API for a single experiment. `PerfConfig` validates the
configuration before processes start, and the legacy `Dict` form remains
supported.

```julia
using PerfChecker, Chairmarks

result = @check PerfConfig(:chairmark; path = @__DIR__, samples = 30) begin
    using MyPackage
    input = make_fixture()
end begin
    MyPackage.process(input)
end
```

### Feature suites

`SoftwareSuite` is the scalable workflow. It represents multiple features,
versions and packages, produces an inspectable plan, and writes portable run
bundles. Use it for CI, historical comparisons and shared interfaces.

## Evidence, not screenshots

Plots are views over structured evidence. Every observation retains its case,
target, metric definition, unit, runtime and provenance. This lets a CI rule, a
web plot and an AI agent reason over the same fact without scraping a chart.

The primary portable contracts are:

- `perfchecker-suite-plan/1` — what should run;
- `perfchecker-progress/1` — what is running;
- `perfchecker-run-bundle/1` — immutable evidence and artifacts;
- `perfchecker-plot/1` — backend-neutral visualization data;
- `perfchecker-query/1` — bounded evidence selection;
- `perfchecker-document-block/1` — documentation projection;
- `perfchecker-provider-result/1` — external measurement ingestion.

## What to read next

- [Install PerfChecker](installation.md).
- Build [your first feature check](first-check.md).
- Model a [complete software suite](../software-suites.md).
- Browse the [measurement catalog](../reference/checks.md).
- Choose an [interactive interface](../interfaces/vscode.md).
