# REPL and Pluto

PerfChecker keeps interactive selection available when VS Code or a web browser
is not the right tool. Both interfaces operate on `SuitePlan` and produce the
same bundles and reports as CI.

## REPL workflow

```julia
using PerfChecker

suite = load_software_suite("perf/suite.jl")
plan = plan_suite(suite; profile = :quick)
selected = configure_suite_repl(plan)
result = run_suite_repl(selected; strict = false)
```

The configurator lets you filter packages, business features, check types, and
targets. It prints the resolved plan before execution and reports progress while
workers run. For scripted use, `filter_suite_plan` and `select_suite_plan` apply
the same selection without prompts.

Install UnicodePlots in the controller environment to render terminal-native
summaries:

```julia
using UnicodePlots
terminal_plot(read_run_bundle("perf/results/bundles/my-run"), "plot-id")
```

Terminal plots are a compact fallback; they do not replace hover, linked
selection, or source drill-down in WGLMakie.

## Pluto dashboard

```julia
using PerfChecker, Pluto

notebook = prepare_pluto_dashboard(
    "perf/PerfCheckerDashboard.jl";
    suite_path = "perf/suite.jl",
    factory = :build_suite,
)

launch_pluto_dashboard(notebook)
```

The generated notebook is an editable controller surface. It can select and run
features, show progress, load bundles, and construct plots while the measured
work continues to execute in fresh Malt workers. Commit the generated notebook
only when it is meant to be a maintained project interface; otherwise regenerate
it from the suite.
