# Measurement model

PerfChecker models performance as a product of dimensions, not as one generic
time or memory number:

```text
resource × lifecycle phase × execution regime × scope × method × statistic
```

For example, startup, import, compilation, first execution, and steady-state
time are different measurements. Julia heap bytes, native heap bytes, process
RSS, and GPU memory are also different resources. A report may display them
together, but it may not silently add or compare them.

## Required measurement context

Every measurement definition should state:

- metric ID, canonical unit, collector and definition version;
- phase: resolve, install, precompile, startup, import, first execution,
  steady state, endurance, or shutdown;
- regime: clean depot, cached depot/fresh process, warm process, or steady state;
- scope: expression, method, feature, task, process, process tree, interface,
  service, database, or device;
- clock or counter source and whether collection is exact, repeated, sampled,
  static, or estimated;
- sample and aggregation semantics;
- whether compilation, GC, child processes, GPU synchronization, loopback, and
  protocol overhead are included;
- expected perturbation, required privileges, and incompatible collectors;
- runtime, source, dependency, artifact, platform, hardware, thread, cache, and
  environment provenance;
- a semantic outcome proving that both candidates performed equivalent work.

Values are numerically comparable only when their versioned measurement
definitions and comparison keys permit it.

## Julia performance families

| Family | Evidence kept distinct | Typical collector or adapter |
| --- | --- | --- |
| Warm CPU execution | latency distribution, throughput, CPU user/system, GC | BenchmarkTools, Chairmarks, Julia timers |
| Startup and import | bare startup, project activation, `using`, `__init__`, extension load | fresh processes, `@time_imports` |
| Compilation and TTFX | first execution, inference, code generation, recompilation, dynamic dispatch | trace flags, SnoopCompileCore, JET |
| Precompile and images | `Pkg.precompile`, cache hit/miss, `.ji`/native image size, sysimage and app size | PrecompileTools, PkgCacheInspector, PackageCompiler |
| Inference and invalidation | inference time, unstable returns, dispatch sites, invalidation trees and consequential recompilation | JET, SnoopCompileCore, Cthulhu links |
| CPU profiles | self/cumulative samples, task/thread, Julia and native frames | `Profile`, PProf, Speedscope |
| Scheduling and waiting | runnable/running/waiting tasks, locks/channels, fairness and saturation | wall-time profile, task metrics when supported |
| Julia allocation and GC | bytes/count per operation, allocation sites/types/stacks, pauses and sweeps | `Profile.Allocs`, `@allocated`, AllocCheck diagnostics |
| Heap and process memory | Julia heap, retained objects, RSS/commit peak, page faults, native heap | heap snapshots, process sampler, platform profilers |
| Microarchitecture | cycles, instructions, IPC, cache/TLB/branch misses, migrations, bandwidth/NUMA | LinuxPerf, LIKWID, ThreadPinning |
| File and storage I/O | logical/physical bytes, operations, latency, warm/cold cache and compression | application counters plus OS/process adapters |
| Network and services | payload/interface/wire bytes and packets, connections, retries, retransmissions, client/server latency | explicit workload counters, isolated interfaces, ETW/eBPF providers |
| GPU/accelerator | device compile, launch, kernel, transfer, synchronization, occupancy and VRAM | CUDA/AMDGPU and vendor profilers |
| Parallel/distributed | speedup, efficiency, strong/weak scaling, worker startup, serialization and imbalance | thread/process matrices, MPI/vendor tools |
| Energy | joules/run, joules/op, power and energy-delay product | RAPL/LIKWID and vendor tools |
| Domain algorithm | growth with size, time-to-solution, accuracy/residual, iterations/evaluations | workload-declared outcomes |
| Load/endurance | tail latency, backpressure, errors, recovery and memory growth | isolated staged-load scenarios |

Static analyzers emit diagnostics, not timings. An AllocCheck or JET finding can
explain risk or guide attribution, but it is never presented as measured cost.

## Package archetypes

A package or feature can select several archetypes:

- `pure_compute`, `stateful_mutation`, `compiler_heavy`;
- `data_io`, `async_service`, `native_ffi`;
- `accelerator`, `distributed`, `solver_stochastic`;
- `interactive_rendering` and `load_endurance`.

Archetypes select sensible presets but never remove the ability to configure
individual collectors. Stateful and externally visible workloads must define
setup/teardown and semantic outcomes per sample.

## Network accounting

Network measurement is a required candidate feature. PerfChecker distinguishes:

1. `application`: payload bytes, packets/frames, operations and connections
   explicitly reported by the workload;
2. `host_interface`: operating-system interface byte and packet deltas; useful
   immediately, but contaminated by unrelated traffic;
3. `isolated_interface`: the same counters inside a network namespace,
   container, VM, or otherwise dedicated interface; suitable for budgets;
4. `process_tree`: packets/bytes attributed by a platform facility such as ETW
   or eBPF to the worker closure;
5. `wire`: packet capture including transport overhead, opt-in because packet
   metadata can be sensitive.

The built-in `:network` backend covers level 1. The
`:network_interface` backend and `measure_network_interface` cover level 2 on
Windows and Linux. They report bytes, packets, discards, interface, capture
layer and attribution scope. The `:network_isolated` backend and
`measure_isolated_network_command` cover level 3 on native Linux or WSL2 with
a loopback-only namespace or outbound IPv4 through `slirp4netns`. Package-level CI gates require level 3 or 4,
or an otherwise controlled interface; host-interface evidence remains
informative.

Latency is always labeled with its context: in-process, loopback, client
end-to-end, server, DNS/TLS, or scheduler wait. Remote latency can still be
compared in controlled experiments, but is not silently attributed to package
code.

## Native dependency closure

For JLLs, DLLs, C/C++/Fortran/Rust wrappers, embedded databases and services,
PerfChecker follows four layers:

```text
declared package → resolved artifact → loaded native image
                 → spawned process / contacted service
```

`dependency_evidence()` implements the first current-process snapshot: resolved
Pkg packages, reachable `Artifacts.toml` files and loaded shared libraries.
The evidence explicitly says that it does not yet cover children, services or
native heap allocations.

Installation/download/extraction, JLL import, loader activity, FFI first call,
FFI steady-state overhead and native execution are separate phases. A native
comparison eventually fingerprints the effective artifact overrides, binary
digests/build IDs, ABI, symbols, allocator, compiler/linker flags, service
version/configuration and dataset. Julia allocation counters never claim to
cover native allocators.

Release and sanitizer/Valgrind/ETW deep-diagnostic lanes are separate because
instrumentation changes performance. Raw native profiles stay artifacts;
normalized frames retain image/build identity and symbolization status.

## Julia stable versus candidate runtimes

`JuliaRuntimeSpec` introduces a runtime axis separate from package versions.
Moving Juliaup selectors such as `release`, `rc`, and `nightly` are probed in a
fresh process and the exact version, commit, bindir and LLVM version are frozen
in the run plan before workers start.

`julia_runtime_suite_command` builds the isolated child-controller command for
one runtime. PerfChecker loads before the measurement worker starts; its own
compilation is not included in the feature measurement. This avoids relying on
Julia serialization compatibility between a controller and a Malt worker from
different runtime generations.

`run_julia_runtime_campaign` executes the same suite under an explicit baseline
and one or more candidate Julia runtimes, retains the exact version/commit/LLVM
probe for each run, and compares the emitted bundles without treating a runtime
version difference as an automatic incompatibility. The CLI form is:

```sh
julia --project=path/to/PerfChecker bin/perfchecker-julia-campaign.jl \
  --suite=perf/suite.jl --baseline=release \
  --candidate=rc --candidate=nightly --reports=perf/julia-runtimes
```

Optional repeated `--limit=metric=fraction` arguments turn diagnostic deltas
into CI gates. The campaign JSON keeps runtime identity and comparison evidence;
stdout/stderr remain excluded from the default serialized report.

Two campaigns answer different questions:

- strict runtime attribution keeps source, dependency graph, artifacts,
  workload, machine and settings fixed while Julia changes;
- realistic compatibility resolves independently under each Julia runtime and
  reports dependency differences, without attributing their effects to Julia.

Triage proceeds from a confirmed paired regression to CPU/wall/allocation/GC
and compiler evidence, profile differencing, smallest-feature reruns, bounded
bisection where builds exist, and finally either a reproduced MWE or an
investigation bundle that preserves uncertainty.
