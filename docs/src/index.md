# PerfChecker.jl

PerfChecker runs performance checks for Julia packages in isolated Julia
processes. The public entry point is `@check`; it accepts a backend symbol, a
configuration `Dict`, a preparation block, and the block to measure.

```julia
using PerfChecker, BenchmarkTools

config = Dict(
    :path => @__DIR__,
    :tags => [:smoke],
    :samples => 10,
    :evals => 1,
)

result = @check :benchmark config begin
    x = collect(1:100)
end begin
    sum(x)
end
```

The `Dict` interface is intentionally kept for compatibility, but PerfChecker
normalizes it internally before running. Missing required options such as
`:path`, invalid tags, invalid thread counts, and malformed package-version
selectors fail before workers are launched.

## Multi-version Checks

```julia
config = Dict(
    :path => @__DIR__,
    :tags => [:release_comparison],
    :pkgs => ("Example", :custom, [v"1.0.0", v"1.1.0"], true),
)
```

The `:pkgs` tuple is `(name, selector, versions, prefer_latest)`. Supported
selectors are `:custom`, `:patches`, `:minor`, `:major`, and `:breaking`.

## Local Development Branches

Use `:devops` to compare a local branch with released versions. PerfChecker
removes the target package from the copied environment before `Pkg.add` or
`Pkg.develop`, which avoids stale UUID/source state from previous runs.

```julia
config = Dict(
    :path => @__DIR__,
    :pkgs => ("Example", :custom, [v"1.0.0"], true),
    :devops => "Example",
)
```

## CI

Run tests with startup files disabled so user-level packages do not mutate the
test environment:

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
```

```@autodocs
Modules=[PerfChecker]
```
