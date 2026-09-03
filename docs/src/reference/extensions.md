# Extensions and providers

PerfChecker keeps its core small by loading optional Julia integrations through
package extensions.

| Extension | Activated by | Capability |
| --- | --- | --- |
| BenchmarkToolsExt | BenchmarkTools | `:benchmark` collector |
| ChairmarksExt | Chairmarks | `:chairmark` collector |
| DrWatsonExt | DrWatson | parameter naming, cached production, suite runs |
| DocumenterExt | Documenter | generated performance pages and docs builds |
| DocumenterVitepressExt | Documenter + DocumenterVitepress | VitePress-aware docs build |
| MakieExt | Makie | figures for the plot grammar |
| WGLMakieExt | Bonito + Makie + WGLMakie | interactive HTML and hoverable flame graphs |
| OxygenExt | Oxygen + HTTP | browser studio, API, authentication, jobs and agents |
| PlutoExt | Pluto | generated interactive dashboard |
| UnicodePlotsExt | UnicodePlots | terminal plots |
| PProfExt | FlameGraphs + PProf | pprof/folded/speedscope profile artifacts |
| PropCheckExt | PropCheck | reproducible property corpus freezing |
| SuppositionExt | Supposition | reproducible property corpus freezing |

Add optional packages to the **controller** environment that needs them. A
renderer does not become a measured-worker dependency. Collector packages are
loaded in the target worker only when that backend requires them.

## DrWatson

```julia
using PerfChecker, DrWatson

params = drwatson_parameters(plan)
name = drwatson_savename(params)
result = drwatson_produce_or_load(plan, "perf/results")
```

`drwatson_run_suite` combines structured experiment parameters, resumable output,
and the normal PerfChecker runner. Cache reuse remains explicit in run evidence.

## Property-based workloads

PropCheck and Supposition adapters freeze minimized/counterexample inputs into a
portable corpus. This makes a stochastic discovery reproducible before it
becomes a performance fixture. Corpus generation is not mixed into benchmark
sampling; measure the frozen examples in a separate deterministic run.

## Add a Julia backend

A backend implements the hook surface for its `Val{:backend}`:

- `initpkgs` loads required packages in the worker;
- `default_options` declares defaults;
- `prep` prepares fixtures;
- `check` performs measurement;
- `post` normalizes evidence;
- optionally `cleanup` and `stop_before_post` manage exit-flushed artifacts.

The backend must define versioned measurement definitions, units, preference,
scope, perturbation, capability checks, deterministic fixtures, and TestItems.
It should return data through the common bundle grammar before gaining UI or CI
claims.

## Add another programming setup

Use `ExternalCommandSpec` and `perfchecker-provider-result/1`. Qualify each
provider independently with a capability manifest and conformance suite. The
shared protocol is deliberately language-neutral, while measurement semantics
remain specific to the actual runtime and tools.
