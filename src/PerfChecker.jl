module PerfChecker

# SECTION - Imports
using BenchmarkTools
using CSV
using DataFrames
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
import Distributed: remotecall_fetch, addprocs, rmprocs
import CoverageTools: analyze_malloc_files, find_malloc_files

struct CheckerOptions
    threads::Int
    path::AbstractString
    targets::Union{String, Vector{String}}
end

# SECTION - Exports
export alloc_check
export alloc_plot
export bench_plot
export store_benchmark
export @prep 
export CheckerOptions

# SECTION - Includes

include("init.jl")

include("allocations.jl")
include("benchmarks.jl")
include("utils.jl")

end
