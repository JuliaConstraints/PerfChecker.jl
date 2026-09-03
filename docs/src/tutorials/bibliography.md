# Bibliography suite walkthrough

The Bibliography example demonstrates the intended shape of a software suite:
one public product surface composed from three directly related Julia packages.

```text
Bibliography software suite
├─ BibInternal
├─ BibParser
└─ Bibliography
```

Each package owns its workloads and version history. The top-level suite combines
them so a change can be evaluated both locally and across the public software
surface.

## Business features and check types

Bibliography declares features such as:

- `import_bibtex`;
- `export_bibtex`;
- `web_render`;
- `read_and_filter`.

The same workload can then be evaluated with BenchmarkTools, Chairmarks,
line-allocation attribution, CPU profiling and Julia 1.12 wall-time profiling.
The `workload` field binds technical feature specifications back to the stable
business feature:

```julia
benchmark = FeatureSpec(
    :import_bibtex;
    entrypoint = "perf/features/import_bibtex.jl",
    comparison_key = "bibliography-import/v1",
)

allocations = FeatureSpec(
    :import_bibtex_allocations;
    workload = :import_bibtex,
    backend = :profile_alloc,
    variants = benchmark.variants,
    options = Dict(:targets => ["Bibliography"], :repeat => true),
)
```

The UI therefore shows `import_bibtex` once, with independent check-type
checkboxes.

## Historical package compatibility

Some features do not exist in old releases. `FeatureVariant` supplies different
workload implementations over version windows, while `julia_since` and
`julia_until` constrain runtime-dependent collectors.

Direct dependency releases are pinned per public Bibliography version. This is
important: measuring an old top-level version against arbitrary modern direct
dependencies can produce a resolver error or a configuration that never existed
for users.

```julia
release_pins = Dict(
    v"0.4.0" => Any[
        (name = "BibInternal", version = v"0.4.0"),
        (name = "BibParser", version = v"0.3.0"),
    ],
)
```

Resolver failures are retained as compatibility evidence. They are not benchmark
failures and are not replaced with a nearby version.

## Build the complete suite

```julia
function bibliography_software_suite()
    SoftwareSuite(
        :bibliography,
        [bibinternal_perf_suite(), bibparser_perf_suite(), bibliography_perf_suite()];
        description = "Bibliography public software surface",
    )
end

build_suite() = bibliography_software_suite()
```

## Run a bounded first pass

Start by inspecting a quick plan:

```sh
perfchecker plan --suite=perf/suite.jl --profile=quick
perfchecker preflight --suite=perf/suite.jl --profile=quick \
  --output=perf/results/quick/compatibility.json
```

Then select a package, business feature, check type and version range in VS Code,
the Oxygen Studio or `configure_suite_repl`. The same selection can be stored in
`perf/perfchecker-ui.json` and replayed in CI:

```sh
perfchecker run --suite=perf/suite.jl --profile=ci \
  --config=perf/perfchecker-ui.json --reports=perf/results/ci
```

## Read the result

For each selected run, inspect:

1. status and worker output;
2. sample distribution rather than only the median;
3. timing, allocation count/bytes and GC fraction together;
4. allocation share by source file and exact line;
5. CPU or allocation flame stacks;
6. runtime dispatch and non-concrete inference as separate diagnostics;
7. differences against the selected release or revision group.

The suite-level conclusion should be derived from explicit thresholds and
availability rules. A visually interesting change is a lead for investigation,
not by itself a regression verdict.
