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

# SECTION - Exports
export bench_plot
export store_benchmark
export @check

# SECTION - Includes

include("init.jl")

include("check.jl")
include("benchmarks.jl")
include("utils.jl")

end

