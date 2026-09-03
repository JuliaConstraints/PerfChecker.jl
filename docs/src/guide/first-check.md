# Your first feature check

This tutorial turns one real package operation into a small, reproducible suite.
The same files will work from Julia, the CLI, VS Code and Oxygen.

## 1. Generate the workspace

```sh
julia --project=/path/to/PerfChecker.jl \
  /path/to/PerfChecker.jl/bin/perfchecker.jl init --root=/path/to/MyPackage
```

The generated smoke workload is immediately runnable. Replace it with a feature
that users of the package recognize.

## 2. Write the workload

Create `perf/features/parse_file.jl`:

```julia
using MyPackage

function perf_setup()
    fixture = joinpath(@__DIR__, "fixtures", "medium-input.txt")
    return read(fixture, String)
end

perf_workload(input) = MyPackage.parse_document(input)
```

`perf_setup()` runs before measurement. `perf_workload(value)` is the operation
evaluated by the selected backend. Keep the fixture deterministic, avoid network
access unless the check is explicitly a network check, and make the returned
value observable so the compiler cannot erase the work.

## 3. Declare the business feature

Edit `perf/suite.jl`:

```julia
using PerfChecker

function build_suite()
    package_root = normpath(joinpath(@__DIR__, ".."))
    feature = FeatureSpec(
        :parse_file;
        description = "Parse a representative document",
        backend = :benchmark,
        entrypoint = joinpath(@__DIR__, "features", "parse_file.jl"),
        comparison_key = "parse-file/v1",
        options = Dict(:samples => 30, :evals => 1, :seconds => 0.5),
    )
    package = PackageSuite(
        "MyPackage";
        source = package_root,
        environment = joinpath(@__DIR__, "runner"),
        versions = :all,
        include_dev = true,
        features = [feature],
    )
    return SoftwareSuite(:my_package, [package];
        description = "MyPackage public performance surface")
end
```

`comparison_key` identifies semantically comparable measurements. Change it
when the workload definition changes enough that old numbers should no longer
be compared.

## 4. Add another check type

Keep `:parse_file` as the business feature and attach another technical check:

```julia
allocations = FeatureSpec(
    :parse_file_allocations;
    workload = :parse_file,
    description = "Attribute parse allocations to source lines",
    backend = :profile_alloc,
    entrypoint = joinpath(@__DIR__, "features", "parse_file.jl"),
    comparison_key = "parse-file/v1",
    options = Dict(:targets => ["MyPackage"], :track => "user", :repeat => true),
)
```

Add `allocations` to `features`. Interfaces now display one `parse_file` feature
with BenchmarkTools and allocation-profile checkboxes.

## 5. Inspect before running

```sh
julia --project=perf /path/to/PerfChecker.jl/bin/perfchecker.jl plan \
  --suite=perf/suite.jl --profile=quick

julia --project=perf /path/to/PerfChecker.jl/bin/perfchecker.jl preflight \
  --suite=perf/suite.jl --profile=quick \
  --output=perf/results/preflight/compatibility.json
```

The plan marks unavailable feature/version pairs rather than silently substituting
a different workload. Preflight identifies resolver and compatibility blockers
before timing begins.

## 6. Run and open the evidence

```sh
julia --project=perf /path/to/PerfChecker.jl/bin/perfchecker.jl run \
  --suite=perf/suite.jl --profile=quick --reports=perf/results/quick
```

The report directory contains a suite summary, JUnit XML, version series,
comparisons and one integrity-protected bundle per run. Open it in VS Code or
serve it through Oxygen to explore samples, source lines and profiles.

## Common first-run mistakes

- Measuring setup or compilation unintentionally: warm representative methods
  in `perf_setup`, or define startup as the metric on purpose.
- Comparing different outputs: assert or record correctness separately from
  performance.
- Using tiny fixtures that optimize away real behavior.
- Changing a workload without changing its `comparison_key`.
- Running historical versions without dependency pins when the package's public
  dependency surface changed.
