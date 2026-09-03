# Makie and interactive plots

Plots are built from a presentation-neutral grammar. `plot_catalog` discovers
valid views for a bundle, `performance_plot` materializes one view model, and
renderers turn that model into Makie figures, interactive HTML, terminal plots,
or documentation blocks.

```julia
using PerfChecker, Makie, WGLMakie

bundle = read_run_bundle("perf/results/bundles/my-run")
catalog = plot_catalog(bundle)
plot_id = first(catalog)["id"]

model = performance_plot(bundle, plot_id)
figure = performance_figure(model)
html = performance_plot_html(model)
```

## Available views

| Family | Views |
| --- | --- |
| Benchmarks | trajectories, sample distributions, candidate delta, metric trade-off |
| Allocations | percentage pie, totals by file, hotspots by line, line heatmap, allocation flame graph |
| Profiles | CPU flame graph, wall-time flame graph |

Every catalog entry is derived from evidence actually present in the bundle.
An unavailable collector therefore does not produce an empty decorative chart.

## Linked inspection

Interactive flame cells, pie slices, points, and bars expose detailed tooltips.
For flame graphs, hover or keyboard focus reveals the complete call path, source
file and line, absolute weight, and percentage. Colours distinguish ordinary
frames from allocation-only evidence and, when present, runtime dispatch,
inference instability, and garbage collection. A visible legend documents the
active colour semantics.

Allocation analysis follows a useful drill-down path:

```text
percentage slice → file → line hotspot → allocation stack → source
```

Filters and selected versions are serializable so another interface can reopen
the same view. Static Makie export remains available for CI artifacts and print
documentation.

<figure class="doc-screenshot">
  <img src="/assets/screenshots/allocation-pie.png" alt="Allocation percentage pie chart produced from a PerfChecker result" loading="lazy">
  <figcaption>Allocation shares stay connected to their file and line evidence rather than becoming an isolated image.</figcaption>
</figure>

## Rendering boundary

Makie, WGLMakie, and Pluto run in the controller. They are not installed into
every target worker merely because a result is visualized. A worker receives the
target package, workload, and the selected collector only; visualization happens
after the result crosses the run-bundle boundary.
