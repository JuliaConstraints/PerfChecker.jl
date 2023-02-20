module PerfChecker

# SECTION - Imports
using BenchmarkTools
using CoverageTools
using CSV
using DataFrames
using Distributed
using LibGit2
using OrderedCollections
using PGFPlotsX
using Pkg
using Plots
using Profile
using Random
using StatsPlots
using Term
using TypedTables

# SECTION - Exports
export alloc_check
export alloc_plot
export bench_plot
export store_benchmark

function __init__()
    if isinteractive()
        eval(Meta.parse("""
        function TypedTables.showtable(io::IO, t::TypedTables.Table{NamedTuple{(:bytes, :percentage, :filenames, :linenumbers), Tuple{Int64, Float64, String, Int64}}, 1, NamedTuple{(:bytes, :percentage, :filenames, :linenumbers), Tuple{Vector{Int64}, Vector{Float64}, Vector{String}, Vector{Int64}}}})
            fn = Term.Link.("file://" .* t.filenames, t.linenumbers)
            Term.tprint(io, Term.Table([t.bytes t.percentage fn]; header = ["bytes", "ratio (%)", "filenames (links)"]))
        end
        """))
    end
end

# SECTION - Includes
include("allocations.jl")
include("benchmarks.jl")
include("utils.jl")

end
