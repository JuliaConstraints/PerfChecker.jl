const DEFAULT_TEMPLATE_KINDS = (:benchmark, :chairmark, :alloc, :pluto)
const TEMPLATE_KINDS = (:benchmark, :chairmark, :alloc, :pluto)

function _template_filename(kind::Symbol)
    kind === :benchmark && return "benchmark.jl"
    kind === :chairmark && return "chairmark.jl"
    kind === :alloc && return "alloc.jl"
    kind === :pluto && return "dashboard.jl"
    throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
end

function _template_body(kind::Symbol)
    kind === :benchmark && return """
using PerfChecker
using BenchmarkTools

config = PerfConfig(:benchmark;
    path = dirname(@__DIR__),
    tags = [:local],
    samples = 10,
    evals = 1,
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :chairmark && return """
using PerfChecker
using Chairmarks

config = PerfConfig(:chairmark;
    path = dirname(@__DIR__),
    tags = [:local],
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :alloc && return """
using PerfChecker

config = PerfConfig(:alloc;
    path = dirname(@__DIR__),
    tags = [:local],
    track = "user",
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :pluto && return """
### A Pluto.jl notebook ###
# v1.0.0

# This dashboard intentionally uses the surrounding Julia project instead of
# embedding a notebook-specific package environment.

# ╔═╡ 2d1f2ad8-b86a-4a14-a4a1-7656b3797f58
begin
    import Pkg
    project_path = dirname(@__DIR__)
    Pkg.activate(project_path)
    Pkg.instantiate()

    using PerfChecker
end

# ╔═╡ 31f575d1-d1f2-4ac3-a492-4e91f22f3385
run_check = false

# ╔═╡ 102521ea-6249-46c4-810d-2f4cb2cbd7f4
config = PerfConfig(:benchmark;
    path = project_path,
    tags = [:pluto],
    samples = 10,
    evals = 1,
)

# ╔═╡ 19898c08-010b-419a-b6aa-00e1e6c1cf51
result = if run_check
    @check config begin
        nothing
    end begin
        sum(1:1_000)
    end
else
    nothing
end

# ╔═╡ fddfef1d-8d73-4e28-a975-405dcf70a293
summary = result === nothing ? nothing : summary_table(result)

# ╔═╡ Cell order:
# ╠═2d1f2ad8-b86a-4a14-a4a1-7656b3797f58
# ╠═31f575d1-d1f2-4ac3-a492-4e91f22f3385
# ╠═102521ea-6249-46c4-810d-2f4cb2cbd7f4
# ╠═19898c08-010b-419a-b6aa-00e1e6c1cf51
# ╠═fddfef1d-8d73-4e28-a975-405dcf70a293
"""

    throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
end

"""
    write_template(kind::Symbol; path=nothing, force=false) -> String

Write a Julia performance-checking template and return its path.

Supported template kinds are `:benchmark`, `:chairmark`, `:alloc`, and
`:pluto`. The generated files use `PerfConfig`; no external configuration file
format is introduced.
"""
function write_template(kind::Symbol; path = nothing, force::Bool = false)
    kind in TEMPLATE_KINDS ||
        throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
    target = path === nothing ? joinpath("perf", _template_filename(kind)) : String(path)
    if isfile(target) && !force
        throw(ArgumentError("$target already exists; pass force=true to overwrite it"))
    end
    dir = dirname(target)
    isempty(dir) || mkpath(dir)
    open(target, "w") do io
        write(io, _template_body(kind))
    end
    return target
end

"""
    perf_setup(; dir="perf", kinds=(:benchmark, :chairmark, :alloc, :pluto), force=false)

Create a small Julia-native performance workspace.

This writes benchmark, chairmark, allocation, and Pluto dashboard starter files
by default. It intentionally does not create a `Perf.toml`; options stay in
Julia code through `PerfConfig`. The Pluto dashboard activates the surrounding
Julia project so it can be used as a controlled project-local view over stored
or newly run checks.
"""
function perf_setup(; dir = "perf", kinds = DEFAULT_TEMPLATE_KINDS, force::Bool = false)
    mkpath(dir)
    return [write_template(kind; path = joinpath(dir, _template_filename(kind)), force)
            for kind in kinds]
end
