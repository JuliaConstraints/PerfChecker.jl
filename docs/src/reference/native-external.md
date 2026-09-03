# Native and external dependencies

Julia packages frequently load JLL artifacts, DLLs, shared objects, C/Rust
wrappers, embedded databases, command-line tools, or remote services. A useful
report must distinguish those layers instead of assigning every cost to Julia.

## Capture the visible dependency closure

```julia
using PerfChecker

before = dependency_evidence(phase = "before_import")
using MyPackage
after = dependency_evidence(
    phase = "after_import",
    hash_libraries = false,
)

payload = dependency_evidence_dict(after)
```

The current implementation records:

- resolved Julia packages and whether they are direct, path, repository, or JLL
  dependencies;
- reachable `Artifacts.toml` files, their SHA-256 digest, and binding names;
- shared libraries loaded in the current Julia process, including size and
  architecture;
- optional binary SHA-256 digests when `hash_libraries=true`.

This is evidence, not complete tracing. It does not yet see libraries loaded
only by child processes, remote services, native heap allocations, ABI details,
or compiler/linker flags. The generated payload marks those gaps explicitly.

## Measure native work by lifecycle phase

Keep these phases separate:

1. artifact download, verification, and extraction;
2. package/JLL import and dynamic loader activity;
3. first FFI call and native initialization;
4. steady-state wrapper overhead and native execution;
5. shutdown, flushing, and child-process cleanup.

Pair Julia measurements with provider-specific artifacts when required: native
profiles, sanitizer reports, database query plans, service metrics, or operating
system counters. Instrumented diagnostics should run in a separate lane because
profilers and sanitizers perturb timing.

## External command provider

`ExternalCommandSpec` is the language-neutral escape hatch. PerfChecker launches
a bounded command that emits one `perfchecker-provider-result/1` JSON document.

```julia
spec = ExternalCommandSpec(
    :rust_parser,
    "rust",
    ["cargo", "run", "--release", "--", "perfchecker-result.json"];
    directory = "/path/to/provider",
    timeout_seconds = 600,
)

bundle = run_external_command(spec; bundle_root = "perf/provider-runs")
```

The provider result is validated and normalized into the common run-bundle
grammar. Declaring a command does not make a setup supported: a provider should
also publish a capability manifest, fixtures, conformance tests, version
provenance, and known measurement limits. New language/tool integrations are
therefore added one at a time and qualified on real workloads.

## Databases and services

For SQL or network services, record server version, configuration, schema/data
fingerprint, locality, connection/TLS setup, cache state, and client pool state.
Separate client latency from server execution and transport waiting. When
possible, launch the complete fixture inside an isolated network namespace so
packet and byte budgets cover the same process tree.
