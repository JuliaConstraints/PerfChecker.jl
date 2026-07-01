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
# Open with Pluto.jl, then run benchmark scripts from this project or load
# stored CSV files with csv_to_table.

begin
    using PerfChecker
end

result = nothing

begin
    result === nothing ? nothing : summary_table(result)
end
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
Julia code through `PerfConfig`.
"""
function perf_setup(; dir = "perf", kinds = TEMPLATE_KINDS, force::Bool = false)
    mkpath(dir)
    return [write_template(kind; path = joinpath(dir, _template_filename(kind)), force)
            for kind in kinds]
end
