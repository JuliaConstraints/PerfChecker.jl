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

# SECTION - Includes

include("init.jl")

include("allocations.jl")
include("benchmarks.jl")
include("utils.jl")

end
