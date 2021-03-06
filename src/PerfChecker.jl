module PerfChecker

# SECTION - Imports
using BenchmarkTools
using Coverage
using CSV
using DataFrames
using Distributed
using LibGit2
using OrderedCollections
using PGFPlotsX
using Pkg
using Plots
using PrettyTables
using Profile
using Random
using StatsPlots

# SECTION - Exports
export alloc_check
export alloc_plot
export bench_plot
export store_benchmark

# SECTION - Includes
include("allocations.jl")
include("benchmarks.jl")
include("utils.jl")

end
