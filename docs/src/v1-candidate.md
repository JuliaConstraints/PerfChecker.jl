# V1 candidate

PerfChecker `1.0.0-rc2` is a release candidate for package authors and CI. It
does not publish or mutate package releases. Its central invariant is that the
controller may load plotting, web and orchestration dependencies, while each
measured feature/version run starts in a fresh Malt worker that loads only its
runner environment, target packages and selected backend.

## Supported workflow

Create a suite and inspect its resolved work before measuring:

```sh
julia --project=path/to/PerfChecker bin/perfchecker.jl init --root=path/to/MyPackage
julia --project=path/to/MyPackage/perf path/to/PerfChecker/bin/perfchecker.jl plan \
  --suite=path/to/MyPackage/perf/suite.jl --profile=ci
julia --project=path/to/MyPackage/perf path/to/PerfChecker/bin/perfchecker.jl preflight \
  --suite=path/to/MyPackage/perf/suite.jl --profile=ci \
  --output=path/to/MyPackage/perf/results/compatibility.json
julia --project=path/to/MyPackage/perf path/to/PerfChecker/bin/perfchecker.jl run \
  --suite=path/to/MyPackage/perf/suite.jl --profile=ci \
  --reports=path/to/MyPackage/perf/results/ci
```

`run` performs preflight by default. A declared feature that did not exist in
an older package range, or requires another Julia runtime through
`julia_since`/`julia_until`, is `feature_unavailable` and does not block the run. An
environment that cannot resolve is `unsatisfiable` and blocks measurement. An
unexpected resolver error is `unknown` and also blocks by default.

## Candidate capability matrix

| Capability | Candidate status | Evidence boundary |
| --- | --- | --- |
| Existing `@check` and `PerfConfig` | Supported | Compatibility API retained |
| Feature/package suites and version ranges | Supported | Fresh Malt worker per run |
| JSON, Markdown, JUnit and run bundles | Supported | Versioned common grammar |
| Bundle SHA-256 verification and migration | Supported | Protocol files, not arbitrary external artifacts |
| REPL selection and progress | Supported | Same suite plan grammar |
| VS Code tree and visual editor | Supported candidate extension | Click-to-source, targeted runs, progress, drag ordering and shared document blocks |
| Oxygen Studio and remote pull agents | Supported | Token/TOML authentication; deployment TLS remains operator-owned |
| Pluto, Makie, WGLMakie, Documenter and VitePress | Supported extensions | Never loaded into measured workers unless the workload asks for them |
| Allocation line/file/pie and flame views | Supported when source/profile evidence exists | Hover and type/GC legend in interactive web views |
| Explicit application network counters | Supported | Workload-declared counters |
| Linux/WSL2 isolated packet and byte counters | Supported when namespace tools are available | Complete isolated process tree; outbound mode uses `slirp4netns` |
| Native Windows host-interface counters | Informative | Shared-interface attribution, not a blocking package budget |
| Native Windows per-process packet counters | Unavailable in RC1 | No ETW/WFP claim is made |
| Julia stable/RC/nightly campaigns | Supported | Exact runtime/commit/LLVM probe retained |
| Julia regression source ranking | Supported when source observations exist | Ranked evidence; never asserted to be causal by itself |
| Automatic minimized MWE | Advisory only | A dominant source candidate is reported, human/agent reduction remains required |
| External-language providers | Protocol and process runner supported | Each language/setup still requires a separately qualified provider |

## Run bundles and migration

Every new bundle contains `integrity.json`, with SHA-256 digests for its
manifest, definitions, observations, diagnostics and artifact index. CI should
require it:

```sh
julia --project=path/to/PerfChecker bin/perfchecker.jl verify \
  --bundle=perf/results/run-... --require-integrity=true
```

Legacy bundles remain readable and are explicitly reported as
`legacy_unverified`. Migrate into a new, non-existing directory rather than
overwriting evidence:

```sh
julia --project=path/to/PerfChecker bin/perfchecker.jl migrate \
  --source=perf/legacy/run-... --destination=perf/migrated/run-...
```

The original directory is left untouched. A digest mismatch is a hard read
failure.

The standalone bundle-store ingestion endpoint has a bounded request body and
accepts only UUID run identifiers. Its unauthenticated server form is restricted
to loopback; hosted writable execution uses the authenticated Studio/agent
routes.

## VS Code

The candidate extension lives in the independent
[PerfCheckerVSCode repository](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode).
It resolves the suite through the same CLI and `perfchecker-suite-plan/1`
contract as every other interface.
The tree groups package, business feature, check type and version. The stable
`workload` field keeps `import_bibtex` distinct from the selected BenchmarkTools,
Chairmarks, allocation or profile collector. Selecting a node launches only
that subtree, while selecting a leaf opens its exact entrypoint.

The visual editor adds search, inclusive version filters, stable sorting, colour
labels, global and per-feature check-type selection, drag-and-drop execution
order and progress. It also edits named branch/tag/commit targets and exact or
aggregated reference groups. Output icons exist on suite, package, feature,
check and version nodes. The output panel filters and sorts run summaries,
BenchmarkTools/Chairmarks distributions, version series, comparisons,
allocation pies and flame graphs. Plot points, allocation slices and even narrow
flame cells expose their details on hover and keyboard focus; flame colours
identify dynamic dispatch, non-concrete inference and GC frames.

Saving the editor writes `perfchecker-ui-config/1`, normally to
`perf/perfchecker-ui.json`. Targets, comparison policies, ordered selections and
document blocks are not VS Code-specific:

```julia
blocks = read_document_blocks("perf/perfchecker-ui.json")
documenter_page(bundle, "docs/src/performance.md"; blocks)
# or: documenter_page(bundle, "docs/src/performance.md";
#                     config="perf/perfchecker-ui.json")
```

The saved ordered run selection can also be replayed without VS Code:

```sh
julia --project=perf path/to/PerfChecker/bin/perfchecker.jl run \
  --suite=perf/suite.jl --config=perf/perfchecker-ui.json
```

Oxygen keeps its richer hosted/result exploration interface. VS Code, Oxygen,
REPL, Pluto and Documenter share plans, queries, plot descriptions and document
blocks while retaining interface-specific presentation.

## Measuring PerfChecker with PerfChecker

The repository contains a self-measurement suite in `perf/suite.jl`. It measures
planning, bundle comparison and report-query execution, then attributes the
comparison engine's allocations and CPU stacks. This is self-hosting without
recursive orchestration: the outer controller prepares fresh workers, while the
measured workload only calls pure PerfChecker engine functions.

```sh
julia --project=perf bin/perfchecker.jl run --suite=perf/suite.jl \
  --profile=quick --reports=test/output/self-v1-rc
```

The controller project is `perf/Project.toml`; the copied worker seed remains
the smaller `perf/runner/Project.toml`. The distinction keeps UI and controller
dependencies outside the timed workload.

## Julia candidate investigation

Run the same suite against a known baseline and moving Julia channels:

```sh
julia --project=path/to/PerfChecker bin/perfchecker.jl julia-campaign \
  --suite=perf/suite.jl --profile=quick --baseline=release \
  --candidate=rc --candidate=nightly --reports=perf/results/julia-candidate \
  --resume=true
```

The campaign freezes the runtime version, commit, bindir and LLVM identity. It
writes the paired comparisons plus `julia-investigation.json` and Markdown.
When a candidate exits before writing a bundle, the campaign retains a bounded
diagnostic summary, the first source frames, and classifies the failure (for
example `runtime_crash`, `compatibility`, or `bootstrap_error`). Full worker
output stays excluded from the portable report by default.
With `--resume=true`, a completed runtime is reused only when the suite/profile,
selector, exact Julia version and commit still match and its bundle integrity
verifies. Moving RC/nightly channels are therefore re-run automatically.
Positive source-attributed sample deltas are ranked by file and line. A Julia
Base/compiler frame is called an obvious candidate only when it dominates the
configured evidence share; this is a reduction lead, not proof of causality or
a fabricated MWE.

Every runtime resolves a separate minimal controller project containing the
local PerfChecker checkout and only the suite backends it needs. Manifests are
never shared across Julia versions. Feature-level `julia_since`, `julia_until`
and `julia_excluded` windows turn runtime-specific collectors into explicit
unavailable evidence instead of failures.

## Network budgets

Use application counters for protocol semantics and an isolated namespace for
transport bytes and packets. On Windows the strong-attribution route is WSL2:

```sh
julia --project=path/to/PerfChecker bin/perfchecker.jl network \
  --provider=wsl2_netns --distribution=Ubuntu --external=true \
  --dns=1.1.1.1 --output=perf/results/network.json -- command arguments
```

Outbound isolation requires `slirp4netns`, `unshare`, `nft` and `ip` in the
selected Linux environment. Its user-mode networking overhead is part of the
measurement context. DNS is explicit and configurable; no remote latency is
treated as an intrinsic package property.

## Release gate

Before promoting this candidate to `1.0.0`, the schemas and default blocking
semantics must be frozen, migrations must cover real older bundles, the full
test suite and documentation must pass on supported Julia releases, and at
least one real multi-package suite must pass with newly generated and verified
evidence. Publishing, tagging and branch pushes remain separate maintainer
actions.
