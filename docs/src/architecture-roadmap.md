# Architecture and ecosystem roadmap

Status: design proposal, not an implementation report.  
Snapshot date: 2026-08-28.

## Product thesis

PerfChecker should become the developer-friendly, open-source performance
workbench for Julia packages and package suites. It should work locally first,
run unchanged in generic CI/CD systems, and expose one versioned result grammar
to REPL, notebook, terminal, plotting, forge, and web interfaces.

The Julia package remains the reference engine and the easiest entry point for
Julia package authors. A separate Oxygen-powered service may orchestrate and
render the same protocol. The protocol and server must not assume that every
runner is Julia: after the Julia contract is stable, external runners can add
Python, Rust, or mixed-stack workloads without changing the UI or storage model.

The initial adoption wedge is narrower than this long-term thesis: an author
with an existing PkgBenchmark or PerfChecker suite should obtain a trustworthy
Markdown/JUnit CI verdict in less than ten minutes, without Oxygen and without
rewriting the suite. Protocol and platform work that does not shorten or
strengthen that path is not an early priority.

This leads to five invariants:

1. Supported PerfChecker 0.2.x features keep working during the migration;
   accidental bugs and import-time side effects are not compatibility promises.
2. Collection, comparison, storage, and presentation are separate contracts.
3. Raw evidence is never collapsed into a lossy universal CSV table.
4. A result always states its unit, provenance, collection method, and
   comparability limits.
5. The Oxygen service is a control plane, not a sandbox for arbitrary code.

## What exists today

The current branch already contains valuable foundations:

- `@check` with both dictionary and `PerfConfig` forms;
- isolated Julia processes through Malt;
- registered-version selection (`:custom`, `:patches`, `:minor`, `:major`, and
  `:breaking`), local development targets, and extra packages;
- BenchmarkTools, Chairmarks, allocation tracking, and Makie integrations;
- cached CSV outputs with metadata and hardware identity;
- tags, summaries, REPL helpers, generated scripts, and a Pluto template;
- example histories for GLM and PatternFolds.

These are compatibility commitments for the migration, not code that should be
discarded.

The current implementation also exposes structural limits:

- `CheckerResult` stores backend-specific tables without a backend, run ID,
  metric units, artifact references, or per-target provenance;
- columns with similar names do not always have the same semantics: for
  example, BenchmarkTools and Chairmarks GC fields and time units are not a
  common metric merely because they occupy similarly named columns;
- backend hooks exchange mutable dictionaries and quoted Julia expressions,
  which are useful inside Julia but unsuitable as a stable extension or wire
  protocol;
- CSV is being used simultaneously as raw sample storage, cache payload,
  metadata database, and interchange format;
- the cache fingerprint relies on textual representations and has no atomic
  artifact transaction or explicit schema version;
- the orchestrator captures too little of the effective worker environment to
  determine whether two runs are genuinely comparable;
- package versions can be varied, but Julia versions, commits, runners,
  environments, and package suites are not modeled as a general execution
  matrix;
- comparison, budgets, regression policy, CI exit status, and generic CLI are
  not first-class concepts;
- visualization code understands backend table layouts directly, so every new
  metric would otherwise need custom wiring in every interface;
- temporary environments, cancellation, partial results, retries, and failed
  capabilities need explicit lifecycle handling.

There are also concrete behaviors to classify before promising compatibility:
the import hook creates a machine-local UUID file, that UUID makes cache
identity machine-dependent, workers and copied environments are acquired before
the main protected cleanup region, temporary environment directories are not
removed, all workers are started before largely sequential orchestration,
`find_by_tags` has the wrong shape for searching a result collection, and the
cache omits effective source revision and manifest identity. Phase 0 defines a
supported legacy contract (exports, accepted options, documented semantics,
readable fields and artifacts); defects and undocumented side effects are
explicitly excluded from it.

The baseline test suite passes on Windows with Julia 1.12.7 (46 tests in about
3 minutes 28 seconds on the inspected machine). It also reports that the local
Manifest needs resolving. The long integration path and package installation
belong in a separate CI tier from fast unit and schema-contract tests.

## Architecture options considered

| Option | Strength | Failure mode | Decision |
| --- | --- | --- | --- |
| Rewrite PerfChecker as one larger package | A clean slate can look simple initially | High regression risk, one dependency graph, presentation and execution remain coupled | Reject |
| Evolve the package around explicit domain and port contracts, then add optional adapters | Preserves users and permits incremental verification | Requires temporary adapters and dual formats | **Recommend** |
| Build the polyglot Oxygen platform first and make Julia one remote agent | Starts with the final deployment shape | Delays the package-author experience and freezes a protocol before it is proven | Defer |

The recommended option keeps one repository and package while the core contract
is moving. A separate `PerfCheckerOxygen.jl` package/service should be created
only when the HTTP boundary and its security lifecycle are stable enough to
justify independent releases. A language-neutral protocol repository should be
extracted only after at least two runner implementations prove it.

## Target component model

```text
Julia API / suite file / CLI / CI / Oxygen HTTP
                    |
              Plan and validate
                    |
      SuiteSpec -> RunPlan -> RunAttempt lifecycle
                    |
        Runner port (local Julia, juliaup, container,
                     remote agent, external language)
                    |
       Collector ports + capability negotiation
                    |
     Observations + Diagnostics + Artifact references
                    |
    ArtifactStore / IndexStore / EventSink ports
                    |
       Compare + policy engine (pass/warn/fail/
                  incomparable/unavailable)
                    |
       REPL / Markdown / JUnit / SARIF / Makie /
                 Pluto / Oxygen reporters
```

The package should initially implement these as internal modules, not as a set
of prematurely published micro-packages:

- `PerfChecker.Specs`: suite, case, matrix, collector, and budget definitions;
- `PerfChecker.Protocol`: versioned run envelopes, observations, diagnostics,
  artifact descriptors, and JSON serialization;
- `PerfChecker.Runners`: process lifecycle, Julia/Malt compatibility runner,
  environment preparation, and cancellation;
- `PerfChecker.Collectors`: collector interface and built-in Julia collectors;
- `PerfChecker.Storage`: atomic local bundles, cache index, import/export;
- `PerfChecker.Analysis`: comparability, summaries, deltas, and policy gates;
- `PerfChecker.Reporters`: presentation-neutral report models;
- `PerfChecker.Legacy`: 0.2.x configuration, result, CSV, and plotting adapters.

### Extension contracts

Each extension point should have a small behavior contract rather than a set of
dictionary keys:

```julia
abstract type AbstractRunner end
abstract type AbstractCollector end
abstract type AbstractStore end
abstract type AbstractReporter end

capabilities(component, context)::Vector{Capability}
validate(component, spec)::Vector{Diagnostic}
prepare(component, context)::Prepared
collect(component, prepared, workload)::CollectorResult
finalize(component, prepared, outcome)::Nothing
```

The exact Julia spelling is still reversible. The important decisions are the
lifecycle, typed results, capability negotiation, and the rule that cleanup is
guaranteed after success, failure, timeout, or cancellation.

This interface is a hypothesis until it has represented at least a wrapping
collector (BenchmarkTools), a start/stop profiler (`Profile`), and a static
analyzer (JET). Resource destruction belongs to the runner through a cleanup
ledger that records each acquired process, directory, handle, or collector
token immediately; cleanup must still work when preparation fails before a
fully prepared value exists.

## Common result grammar

The common grammar is an envelope and a stream of typed records, not a single
wide table. Its normative representation should be JSON Schema plus examples;
Julia types implemented with JSON3 and StructTypes are the reference binding.

### Run envelope

A run envelope contains:

- `schema_version`, logical `run_id`, physical `attempt_id`, `reuse_key`,
  timestamps, lifecycle state, and whether evidence was freshly collected or
  reused;
- suite/case IDs and user labels;
- source identity: repository, revision, dirty state, package UUIDs and versions;
- runtime identity: language, runtime version/commit, executable, flags,
  thread pools, BLAS/runtime libraries, and lockfile/manifest digest;
- effective environment: OS, architecture, container/cgroup limits, CPU model
  and topology, available memory, runner identity, relevant environment
  variables, and collector capabilities;
- configuration digest and workload digest;
- immutable snapshots (or content-addressed canonical snapshots) of every
  measurement definition selected by each case, including IDs and versions;
- parent/baseline relationships and tags;
- warnings that affect reproducibility or comparability.

Secrets and arbitrary environment values must never be captured by default.
The environment collector uses an allowlist and redacts known credential forms.

### Record kinds

The protocol needs four record families:

1. `Observation`: scalar, counter, distribution sample, or time-series point.
   It contains a namespaced metric ID, numeric value, explicit unit, aggregation
   kind, sample index/time, scope, attributes, measurement-definition ID, and
   comparison key.
2. `Diagnostic`: rule ID, severity, message, stable fingerprint, source
   location, and structured evidence. JET, AllocCheck, and policy failures map
   here.
3. `Artifact`: content digest, MIME type, size, logical role, producer, URI or
   bundle-relative path, and sensitivity/visibility classification. Profiles,
   heap snapshots, logs, traces, and large sample batches remain artifacts.
4. `Event`: lifecycle and progress state for streaming interfaces. Events are
   not benchmark measurements and can be dropped after run compaction.

Recommended base units follow UCUM/OpenTelemetry conventions (`s`, `By`, `1`,
and derived rates). Display layers may choose nanoseconds or MiB, but stored
values and units remain unambiguous.

Example metric namespaces:

- `process.cpu.time`, `process.memory.rss`, `process.disk.io`;
- `julia.wall.time`, `julia.gc.time`, `julia.alloc.bytes`,
  `julia.alloc.count`, `julia.compile.latency`;
- `julia.inference.runtime_dispatch`, `julia.method.invalidation`;
- `hardware.instructions`, `hardware.cycles`, `hardware.cache.miss`;
- `gpu.kernel.duration`, `gpu.memory.usage`;
- `network.io.payload`, `network.io.transport`, `network.io.wire`.

The three network levels are deliberately distinct: bytes reported by the
application, bytes attributed to a process by the OS, and bytes observed on an
interface are not interchangeable.

A metric name and unit are insufficient to make two values comparable. A
versioned measurement definition also fixes warmup policy, sampling/evaluation
protocol, clock, inclusion of GC/compilation/child processes, attribution
level, sample semantics, estimator, and permitted comparator. A comparison key
includes this definition version. The analysis engine refuses a numeric
comparison when definitions differ unless a dedicated converter/comparator
explicitly accepts both versions.

The bundle is self-describing: the metric registry supports discovery and
governance, but historical meaning never depends on the registry's current
state. Canonical serialization also defines key order, integer encoding beyond
JSON's exactly representable 53-bit range, finite floating-point rules (NaN and
infinities are not JSON numbers), and the precise byte representation used for
SHA-256 digests.

### On-disk bundle

The first portable storage format should be a directory or compressed bundle:

```text
run-<id>/
  manifest.json
  measurement-definitions.json
  observations.jsonl
  diagnostics.jsonl
  artifacts.json
  artifacts/<sha256>.<extension>
```

Writes use a temporary sibling followed by an atomic rename. Every artifact is
content-addressed and verified. JSON Lines supports streaming and simple tools;
an Arrow extension can store large homogeneous sample/time-series batches.
Profiles keep ecosystem-native formats such as pprof protobuf, Chrome CPU
profile, or heap snapshot instead of being flattened into JSON rows.

Cache reuse is separate from identity. `run_id` identifies a requested logical
run, `attempt_id` an actual attempt, and `reuse_key` the evidence that may be
reused. The reuse key covers source/dirty state, effective manifest/lockfile,
runtime and environment compatibility, workload digest, measurement-definition
snapshot, collector version/configuration, and relevant capabilities. Users can
request `fresh`, `reuse`, or policy-controlled reuse. Missing provenance never
causes silent reuse, and reused evidence keeps the producing attempt ID.

CSV remains a supported exporter and legacy reader. During migration, runs are
dual-written to the legacy CSV layout and the new bundle, and contract tests
compare the normalized values.

## Measurement model

PerfChecker should distinguish measurement modes because they perturb programs
differently and answer different questions.

### Built into the Julia engine

- **Environment and reproducibility collector:** runtime, source, dependency,
  effective resource, and hardware identity.
- **Basic timing collector:** wall time, CPU time where available, allocations,
  GC time, result status, and warmup policy using Julia primitives.
- **CPU sampling profile:** `Profile` stdlib, retaining task/thread metadata.
- **Allocation sampling profile:** `Profile.Allocs`, with sampling rate and
  overhead warnings.
- **Heap snapshot:** `Profile.take_heap_snapshot`, stored as an artifact.
- **Legacy line allocation:** the existing `--track-allocation` and
  CoverageTools flow, preserved for compatibility but no longer the default
  deep-memory tool.
- **Process resource sampler:** RSS/peak RSS, CPU user/system time, file I/O,
  threads/children, and context switches when supported by the OS.

Every collector declares estimated overhead, supported platforms, required
privileges, whether it can run concurrently with another collector, and whether
it requires a fresh process.

### Network measurement

Network accounting is useful for HTTP, database, distributed, and artifact
packages, but a cross-platform exact per-package counter does not exist. The
roadmap therefore uses capability levels:

1. `application`: the workload explicitly reports payload bytes or request
   counts; portable and precise for the declared semantic layer;
2. `isolated_interface`: PerfChecker observes a dedicated container/network
   namespace or interface; includes unrelated protocol overhead by design;
3. `process_attributed`: an OS adapter uses an attribution facility such as a
   Linux eBPF/cgroup collector or a platform tracing provider;
4. `unavailable`: the run records why attribution was unsupported rather than
   presenting a host-wide NIC delta as package traffic.

Network observations must record direction, capture layer, loopback handling,
children inclusion, retransmission/overhead semantics, privilege, and sampling
method. Packet payloads and endpoint names are not retained by default.

All network collectors remain experimental and non-blocking initially. A
network budget may fail CI only inside a hermetic runner with controlled
endpoints, fixed child/loopback semantics, and measured background noise.
Otherwise network evidence is diagnostic. Application-reported bytes describe
the workload's semantic payload, not automatically the package's total traffic.

### Comparison and CI policy

A comparison first computes a comparability report, then deltas. Environment
fingerprints have graded compatibility: identical, compatible with warnings, or
incomparable. A CI policy can explicitly override warnings, but the report keeps
them.

Initial statistical summaries should include count, min, median, mean, standard
deviation, MAD, selected quantiles, and confidence interval where the collector
supports it. A gate combines:

- absolute budgets;
- relative change from an explicit baseline;
- collector-specific noise tolerance;
- minimum sample and repetition rules;
- fail/warn policy for missing, unsupported, or incomparable evidence.

The recommended CI experiment is paired A/B execution in the same job and on
the same runner. Baseline and candidate order is alternated or randomized;
warmup, calibration, repetition count, effect-size floor, and stopping rules
are recorded. A downloaded baseline from a different machine is warning or
incomparable by default, not a silent hard gate. Comparator implementations
must match the sample semantics and must not apply an independent-sample test
to paired or serially correlated measurements.

The outcome vocabulary is `pass`, `warn`, `fail`, `incomparable`, `unavailable`,
or `error`. CI reporters map it to exit codes, Markdown, JUnit XML, and SARIF
without embedding forge-specific logic in the analysis engine.

## Ecosystem adoption matrix

Versions below are the latest registered versions in the inspected General
registry snapshot. Version freshness is evidence, not a guarantee of API
stability; every adopted integration still needs a pinned compatibility range
and contract tests.

### Core or immediate migration dependency

| Library | Snapshot | Use | Decision |
| --- | ---: | --- | --- |
| Tables.jl | 1.12.1 | Standard tabular interface for summaries/exporters | Add to core for tabular views; protocol structs remain the public result model and no concrete table type is mandated |
| JSON3.jl | 1.14.3 | Fast JSON and typed serialization | Add to core for the protocol; retain JSON.jl only for compatibility during migration |
| StructTypes.jl | 1.11.0 | Explicit mappings for versioned protocol structs | Add to core |
| Malt.jl | 1.x (existing) | Isolated Julia worker mechanism | Keep behind `JuliaMaltRunner`; do not make it the language-neutral runner API |
| CoverageTools.jl | 1.x (existing) | Legacy line allocation parsing | Keep until the legacy collector can become optional without breaking users |
| CSV.jl | 0.10 (existing) | Legacy import/export | Keep as compatibility/export format, not canonical storage |

### First-party optional collectors and analyzers

| Library | Snapshot | Best integration | Decision |
| --- | ---: | --- | --- |
| BenchmarkTools.jl | 1.7.0 | Distribution collector and existing suite importer | Keep and upgrade the extension to typed observations |
| Chairmarks.jl | 1.3.1 | Lightweight distribution collector | Keep and normalize units/semantics explicitly |
| Julia `Profile` stdlib | runtime | CPU, allocation, heap, task/thread evidence | Make built-in collectors; no optional dependency required |
| AllocCheck.jl | 0.2.3 | Static allocation diagnostics for known call signatures | Add an optional diagnostic extension |
| JET.jl | 0.11.3 | Reproducible static optimization diagnostics | Add an optional diagnostic extension; isolate its version-sensitive internals |
| SnoopCompileCore.jl | 3.1.1 | Dynamic inference, invalidation, and latency evidence | Add a fresh-process compiler collector; prefer the core package where sufficient |
| PkgCacheInspector.jl | 1.2.1 | Inspect precompile cache content/size | Experimental compiler-artifact collector |
| TimerOutputs.jl | 0.5.29 | Import user-instrumented named regions | Add an ingestion adapter, not a mandatory timing engine |
| LinuxPerf.jl | 0.4.2 | Linux process hardware counters | Experimental Linux extension with capability checks |
| LIKWID.jl | 0.4.6 | HPC counters, topology, energy, pinning | Experimental Linux/HPC extension; require explicit privilege and pinning report |
| ThreadPinning.jl | 1.1.1 | Reproducible thread placement/topology | Optional runner control on Linux; record no-op/limitations elsewhere |
| CUDA.jl / AMDGPU.jl | current | GPU timing, memory, kernels, device provenance | Separate vendor extensions after the CPU protocol is stable |

PAPI.jl is not selected for the first hardware-counter implementation: its
latest registered release is 0.3.0 from 2021, while LinuxPerf and LIKWID have
more recent registered releases and clearer immediate scopes. It can be added
later by satisfying the same collector contract.

### Importers, exporters, and user interfaces

| Library | Snapshot | Use | Decision |
| --- | ---: | --- | --- |
| PkgBenchmark.jl | 0.2.15 | Existing BenchmarkTools suites and revision comparison | Interoperate/import; do not duplicate its suite convention unnecessarily |
| AirspeedVelocity.jl | 0.6.5 | Commit-history and load-time workflows | Import results or provide a runner adapter; use as a UX reference |
| PProf.jl | 3.2.0 | Portable pprof artifacts and interactive web viewer | Preferred profile artifact exporter |
| FlameGraphs.jl | 1.1.0 | Shared flamegraph representation | Optional profile transformation layer |
| ProfileCanvas.jl | 0.1.7 | Browser display for CPU/allocation profiles | Optional local reporter/reference UI |
| ProfileView.jl | 1.10.3 | Interactive desktop analysis | Document compatibility; avoid a core dependency |
| ProfileSVG.jl | 0.2.2 | Static SVG profile output | Optional static reporter |
| ChromeProfileFormat.jl | 1.0.1 | `.cpuprofile` export | Optional artifact exporter |
| FirefoxProfileFormat.jl | 1.0.0 | Firefox profile interchange | Evaluate after the base profile contract is complete |
| Arrow.jl | 2.8.1 | Efficient large sample/time-series batches | Optional storage/export extension |
| Makie.jl | 0.21/0.22 (existing) | Current plots and richer dashboards | Preserve; rewrite against report models, not backend tables |
| Oxygen.jl | 1.10.1 | OpenAPI HTTP control plane and web service | Separate optional service package once the protocol is stable |
| OpenTelemetry.jl | 0.4.0 | Export live operational telemetry | Optional exporter only; implementation is unofficial and benchmark artifacts are not ordinary service metrics |
| Prometheus.jl | 1.4.1 | Current gauges/counters for a running service | Oxygen operational metrics, not canonical benchmark storage |

`ProfileEndpoints.jl` 2.6.0 is a useful interoperability reference for
profiling live Julia services and pprof/heap artifacts. PerfChecker should not
copy its endpoints into the core; an Oxygen deployment may proxy or import such
artifacts when profiling an already-running service is in scope.

### Reference-only or deferred

- Cthulhu is excellent interactive investigation, but its interactive descent
  is not a deterministic CI collector. Link diagnostics to a reproduction
  command instead of depending on it.
- BenchmarkCI is GitHub-oriented and its latest registered release is old;
  implement generic CI reporters and document adapters instead.
- BenchPerf demonstrates `perf stat` per benchmark but has a small, old release;
  reuse the concept through LinuxPerf/runner wrappers, not the dependency.
- PerformanceTestTools demonstrates why compiler checks need a clean subprocess;
  PerfChecker already owns that lifecycle and should implement the invariant
  directly.
- StatProfilerHTML, CpuMemMonitor, and MemoryInspector are not selected as core
  dependencies; their useful presentation or sampling concepts can be covered
  by the protocol and more active lower-level components.
- PackageCompiler is a target to measure (build time, output size, load time),
  not a dependency of every PerfChecker installation.

## Developer experience

The package should support three equivalent entry paths:

1. Julia-native API for scripts, tests, and notebooks;
2. a declarative `perf/Perf.toml` plus Julia workload entrypoint;
3. a `perfchecker` CLI for local and CI use.

The proposed division is intentional: TOML stores metadata, matrices,
collector settings, policies, and references; Julia code registers named cases,
fixtures, setup, and workloads. TOML is not expected to serialize closures or
Julia expressions. Stable case IDs are explicit and changing workload code
changes its digest without silently changing its human identity.

Proposed workflow:

```text
perfchecker init
perfchecker plan
perfchecker run --output .perf/runs
perfchecker compare --baseline main --target HEAD
perfchecker check --policy perf/Policy.toml --report markdown --report junit
perfchecker serve                    # only when Oxygen integration is installed
```

The first end-to-end UX proof should be even smaller for an existing suite:

```text
perfchecker init --from-pkgbenchmark
perfchecker check --baseline main --target HEAD \
  --report perf-report.md --report perf-junit.xml
```

Those commands are a target contract, not implemented syntax. The design gate
is that they leave the existing `benchmark/benchmarks.jl` unchanged, complete
without Oxygen, and produce an explicit comparable/incomparable verdict.

`init` should recognize an existing PkgBenchmark-style suite and offer an
adapter instead of forcing users to rewrite it. Generated files must be small,
commented, deterministic, and safe to commit. A package author can start with a
single case and timing collector; deep collectors remain opt-in presets such as
`quick`, `ci`, `profile`, `compiler`, `hpc`, and `gpu`.

### Reference package-suite scenario

The first native package-suite example is the local Bibliography family:

- `Bibliography` 0.4 is the product-level package;
- its direct domain dependencies are `BibInternal` 0.4 and `BibParser` 0.3;
- `BibParser` also depends on `BibInternal`, which exercises transitive change
  attribution instead of treating the suite as three unrelated packages.

None of these packages currently contains a dedicated benchmark suite, so this
scenario validates the new-package path rather than the PkgBenchmark importer.
It starts with a bounded, deterministic corpus derived from committed fixtures,
then adds generated small/medium/large corpora whose generator seed and digest
are recorded in the run bundle. Proposed cases are:

| Layer | Representative workloads | Primary evidence |
| --- | --- | --- |
| BibInternal | entry construction, field normalization, validation, profile composition | latency distribution, allocations, compiler diagnostics |
| BibParser | BibTeX/BibLaTeX parse, format detection, and optional CFF/CSL/XML parsers | throughput in bytes and entries per second, latency, allocations, CPU profile |
| Bibliography | read/validate/filter/sort/write and parse-to-export round trips | end-to-end latency, throughput, allocations, phase profile |

The revision matrix has two intentional modes. A lockstep mode compares the
three baseline revisions with the three candidate revisions as a releasable
suite. An attribution mode changes one package revision at a time while pinning
the other two and the effective manifest. Results across incompatible public
APIs or data semantics are `incomparable`, not regressions. Optional format
extensions are separate capabilities and never silently change the core suite.

This example also validates hierarchical identities (`suite/package/case`),
shared fixtures without shared mutable state, per-package and whole-suite
budgets, dependency provenance, partial failure reporting, and a single
Markdown/JUnit summary that still links to package-specific profiles.

The Julia macro API remains convenient, but the persisted suite contains stable
case IDs and entrypoint references rather than serialized `Expr` values. Remote
and polyglot runners never receive arbitrary Julia expressions through the
public HTTP API.

Before a 1.0 release, the project also needs a metric namespace registry,
extension-author contract tests, compatibility/deprecation policy, release
cadence, and documented startup/installation budgets. Otherwise independent
extensions will create semantically overlapping metrics that the common UI
cannot safely compare.

## Oxygen service and polyglot boundary

The first Oxygen service should be read-mostly: ingest completed bundles, list
runs, compare them, stream progress, and serve artifacts/reports. Job execution
comes later through a queue and isolated agents.

Candidate v1 endpoints:

- `GET /v1/capabilities`;
- `POST /v1/runs:ingest`;
- `GET /v1/runs` and `GET /v1/runs/{id}`;
- `GET /v1/runs/{id}/events` (SSE);
- `GET /v1/runs/{id}/artifacts/{artifact_id}`;
- `POST /v1/comparisons`;
- `POST /v1/jobs` only after an isolated runner/queue exists.

Oxygen can publish OpenAPI documentation, but OpenAPI describes the control
plane rather than the full high-volume artifact format. JSON Schema versions
the run grammar; artifact media types version specialized data.

For external languages, a runner adapter is an executable that accepts a
validated run-plan JSON document and emits JSON Lines events plus a final
bundle. The server should authenticate agents, enforce quotas, bound log and
artifact sizes, verify digests, and keep source execution outside its own
process. Network egress policy, secret injection, and artifact retention belong
to the runner deployment, not to suite files.

The run plan is a second protocol, versioned independently from result bundles.
It has its own JSON Schema, capability negotiation, resource/size limits,
validation and compatibility policy. It identifies trusted entrypoints and
content digests; it never carries raw Julia `Expr` values, arbitrary source
snippets, or an implicit shell command. A runner rejects unsupported plan
versions and capabilities before acquiring expensive resources.

Read-only ingestion still handles hostile content. Its non-negotiable
invariants are:

- never dereference a remote artifact URI during ingestion;
- reject absolute paths, `..`, links/symlinks, duplicate archive paths, and
  extraction outside a fresh destination;
- enforce compressed size, expanded size, compression ratio, file count,
  per-file size, JSON nesting, JSONL line length, and processing-time limits
  before indexing;
- verify every digest before making a bundle immutable and visible;
- escape labels/Markdown and prevent stored XSS; serve uploaded SVG/HTML as
  downloads or from a sandboxed origin with a strict CSP;
- authorize by tenant, run, comparison, and artifact rather than only by route;
- quota SSE clients, comparison cost, ingestion concurrency, and retained data;
- distinguish trusted locally produced bundles from hostile imports in the
  audit model even though both must pass structural validation.

Artifact sensitivity is independent of structural validity. Profiles, stack
traces, JET diagnostics, logs, and source paths can disclose usernames,
filesystem layout, symbols, or code. Producers mark artifacts `public`,
`internal`, or `sensitive`; server publication of internal/sensitive artifacts
is an explicit authorized action, not a consequence of ingesting the bundle.

A polyglot envelope enables common transport, storage, and presentation, not
automatic semantic equality across languages. Each comparator lists accepted
measurement-definition IDs. Mixed-stack runs additionally need parent/child or
span correlation and clock/causality metadata; those records are added only
when a real mixed-stack prototype demonstrates their requirements.

## Migration plan

### Phase 0A — prove the adoption wedge and CI signal

Before restructuring the package, build disposable vertical slices around the
current engine:

- import one existing PkgBenchmark suite unchanged and emit Markdown plus JUnit;
- run one existing PerfChecker 0.2.x suite and the Bibliography/BibParser/
  BibInternal reference suite, which has no dedicated performance setup,
  through the proposed happy path;
- prototype one BenchmarkTools distribution, one stdlib CPU profile, one JET
  diagnostic, and one unsupported network capability in the candidate grammar;
- display those same records in REPL, JSON, Markdown, and a minimal read-only
  Oxygen endpoint without interface-specific parsing;
- run a paired baseline/candidate experiment on Windows and Linux, including
  injected 3%, 5%, and 10% regressions and unchanged controls; inject at least
  one regression into BibInternal and demonstrate whether the lockstep and
  one-package-at-a-time matrices attribute its effect correctly through
  BibParser and Bibliography.

Adoption gates separate human setup time from workload duration. A developer
unfamiliar with the design reaches a valid, launched quick-suite plan in at most
10 minutes for an imported suite and 20 minutes for a new package, with no
Oxygen and no suite rewrite. The quick suite has a documented time budget;
PerfChecker orchestration/reporting overhead is reported separately from the
package workload. Setup errors and documentation needs are recorded.

Reliability gates are fixed before public fail-on-regression exit codes: measure
false failures on unchanged paired comparisons, detection power for injected
regressions, PerfChecker overhead, and incomparable rate. Thirty repetitions may
guide an exploratory prototype, but cannot substantiate a below-1% public claim.
That claim requires a predeclared sample size and interval: roughly 300
zero-failure trials only place the one-sided 95% upper bound near 1%, so the
exact interval is always reported. Detection power is also reported with an
interval, not only as a point estimate. The candidate target is at least 90%
detection at a 10% injected regression; observed data may revise thresholds
before release.

Exit gate: the wedge shows both adoption value and a credible CI signal. If it
fails, simplify the product around import/reporting rather than proceeding with
a generic platform.

Rollback: discard the spikes; they are evidence-gathering code, not migration
foundations.

### Phase 0 — freeze behavior and harden the baseline

Deliverables:

- enumerate every exported symbol, configuration key, generated template,
  legacy CSV field, and plot used by 0.2.x;
- add golden fixtures for BenchmarkTools, Chairmarks, allocation, cache,
  metadata, and plots;
- split fast unit/schema tests from network/package-version integration tests;
- fix correctness/lifecycle defects found by those tests, including temporary
  environment cleanup, `show` with missing hardware, tag lookup shape, unknown
  backend validation, unit mismatches, and failed/partial worker cleanup;
- document the supported legacy contract before refactoring it and explicitly
  list excluded bugs, import-time writes, and undocumented side effects.

Exit gate: all existing examples run, golden outputs are archived, and the fast
test tier requires no registry resolution or package downloads.

Rollback: none required; this phase adds tests and targeted fixes.

### Phase 1 — introduce the protocol beside current results

Deliverables:

- typed run/observation/diagnostic/artifact/event models;
- versioned measurement definitions, sample semantics, comparison keys, and a
  minimal governed metric namespace;
- independently versioned result-bundle and execution-plan JSON Schemas,
  JSON3/StructTypes bindings, canonical serialization, and SHA-256
  configuration/workload/definition digests;
- atomic local bundle store and schema migration reader;
- explicit `run_id`, `attempt_id`, and `reuse_key` semantics with `fresh` and
  policy-controlled reuse modes that never silently reuse incomplete evidence;
- legacy `CheckerResult` and CSV adapters;
- dual-write verification for all current backends.

Exit gate: a legacy and a new run normalize to the same time/allocation/GC
values with explicitly tested unit conversions; old CSV histories still load.

Rollback: keep the new path behind an experimental option and continue legacy
writing.

### Phase 2 — separate planning, runners, and collectors

Deliverables:

- `SuiteSpec`, `CaseSpec`, `MatrixSpec`, `RunPlan`, and lifecycle state machine;
- `JuliaMaltRunner` wrapping current behavior;
- matrices for package versions/revisions, Julia executable/version, thread
  configuration, and environment variables;
- capability negotiation, timeouts, cancellation, retries, partial results,
  deterministic cleanup, and bounded parallelism;
- worker-side environment capture and comparability fingerprint.

Exit gate: current `@check` calls route through the adapters and match Phase 1
fixtures; failed workers leave no process or temporary environment behind.

Rollback: select the legacy orchestrator while keeping the protocol/store.

### Phase 3 — package-author CLI and CI contract

Deliverables:

- `init`, `plan`, `run`, `compare`, `check`, and `report` commands;
- TOML suite/policy files and a Julia workload API;
- generic exit codes, Markdown, JSON, JUnit, and SARIF reporters;
- local-baseline, downloaded-artifact, and same-job baseline workflows;
- GitHub Actions, GitLab CI, and generic shell examples without forge logic in
  the core;
- migration guide for existing PkgBenchmark and PerfChecker suites.

Exit gate: a new package can install PerfChecker, generate a one-case suite,
run locally, and gate a CI job without Oxygen.

Rollback: generated files can invoke the legacy adapter; reporters consume the
stable protocol independently of the runner.

### Phase 4 — deep Julia and system collectors

Order:

1. stdlib CPU/allocation/heap profiles and process resources;
2. AllocCheck and JET diagnostics;
3. load/precompile/invalidation collectors with SnoopCompileCore and optional
   PkgCacheInspector;
4. PProf, Chrome profile, static profile, and Arrow artifact exporters;
5. LinuxPerf/LIKWID and thread-pinning controls;
6. CUDA and AMDGPU collectors;
7. experimental network providers with isolated integration tests.

Each extension has platform/Julia-version matrices, capability tests, overhead
metadata, and a fallback that reports `unavailable` without failing unrelated
collectors.

Exit gate: installing or failing to support one extension cannot change core
results or prevent other collectors from completing.

Rollback: disable a collector by plan/preset; bundles remain readable because
unknown metric namespaces and artifacts are forward-compatible.

### Phase 5 — reporters and Oxygen

Deliverables:

- rebuild Makie and Pluto views against report models;
- read-only Oxygen ingestion, browsing, comparison, SSE, and OpenAPI;
- authentication, quotas, digest verification, retention, and operational
  Prometheus/OpenTelemetry hooks;
- only then add queued jobs and isolated pull-based runner agents.

Exit gate: the web UI contains no collector-specific parsing and cannot execute
uploaded source inside the Oxygen process.

Rollback: the server is optional; bundles, CLI, CI, REPL, and notebooks remain
fully usable without it.

### Phase 6 — validate and extract the polyglot protocol

Deliverables:

- one non-Julia runner and one mixed-stack example;
- cross-language conformance fixtures;
- protocol compatibility policy and independent specification release;
- decision on extracting `PerfCheckerProtocol` and `PerfCheckerOxygen` packages.

Exit gate: Julia and the second runner produce bundles consumed unchanged by
the same storage/UI; comparisons occur only where an accepted measurement
definition and comparator make their semantics compatible.

Rollback: keep the protocol version embedded in PerfChecker.jl until the second
implementation is credible.

## Verification strategy

- **Compatibility:** golden fixtures and deprecation tests for every current
  exported API and data/plot workflow.
- **Protocol:** JSON Schema examples, round trips, unknown-field tests,
  cross-version migration tests, and corrupt/truncated bundle tests.
- **Lifecycle:** injected failures at prepare/run/collect/finalize, cancellation,
  timeout, worker crash, disk full, and duplicate writer scenarios.
- **Platforms:** Julia LTS/stable/pre on Linux, Windows, and macOS; platform-only
  collectors run only where their capability can be established.
- **Statistical:** deterministic synthetic distributions, paired A/B order
  tests, unchanged-run false-positive estimation, injected-regression power,
  and repeated physical smoke tests; CI does not assert exact timings.
- **Security:** malicious paths, oversized artifacts, digest mismatch, secret
  redaction, decompression bombs, symlinks, stored-XSS payloads, hostile
  metadata, tenant authorization, quota exhaustion, and untrusted boundaries.
- **Self-performance:** startup, planning, serialization, and storage overhead
  budgets for PerfChecker itself.
- **Documentation:** every preset and report is executable as a doctest or
  integration fixture.

## Critical decisions still to validate

1. What is the smallest Julia case-registration API that supports stable IDs,
   fixtures, interpolation, and workload digests without serializing closures?
2. Should the first comparison estimator build on BenchmarkTools judgement or a
   small protocol-native robust summary with collector-specific adapters?
3. Is `juliaup` a required Phase 2 runner or an optional adapter, especially on
   CI images where Julia is already provisioned?
4. Which store should the first Oxygen deployment use after local bundles:
   filesystem plus SQLite index, or PostgreSQL plus object storage? This is a
   deployment decision and should not leak into the protocol.
5. Which non-Julia runner is the best transport/storage/UI conformance test?
   Python has the largest
   adoption value; Rust provides a stricter low-level and artifact-format test.

The experiments and measurable gates that precede broad implementation are in
Phase 0A. They are product and statistical evidence, not ceremonial prototypes.

## Primary references

- [Julia profiling manual](https://docs.julialang.org/en/v1/manual/profile/)
- [BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl)
- [PkgBenchmark.jl](https://github.com/JuliaCI/PkgBenchmark.jl)
- [AirspeedVelocity.jl](https://github.com/MilesCranmer/AirspeedVelocity.jl)
- [JET optimization analysis](https://github.com/aviatesk/JET.jl/blob/master/docs/src/optanalysis.md)
- [SnoopCompile.jl](https://github.com/JuliaDebug/SnoopCompile.jl)
- [AllocCheck.jl](https://github.com/JuliaLang/AllocCheck.jl)
- [PProf.jl](https://github.com/JuliaPerf/PProf.jl)
- [ProfileEndpoints.jl](https://github.com/JuliaPerf/ProfileEndpoints.jl)
- [LIKWID](https://github.com/RRZE-HPC/likwid)
- [ThreadPinning.jl](https://github.com/carstenbauer/ThreadPinning.jl)
- [Tables.jl](https://github.com/JuliaData/Tables.jl)
- [JSON3.jl and StructTypes.jl](https://github.com/quinnj/JSON3.jl)
- [Oxygen.jl](https://github.com/OxygenFramework/Oxygen.jl)
- [OpenTelemetry process metric conventions](https://github.com/open-telemetry/semantic-conventions/blob/main/docs/system/process-metrics.md)
