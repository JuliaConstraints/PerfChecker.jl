module PerfChecker

# SECTION - Imports
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
import TypedTables: Table, showtable
import Distributed: remotecall_fetch, addprocs, rmprocs
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo

# SECTION - Exports
export alloc_check
export alloc_plot
# export bench_plot
# export store_benchmark
export @check
export to_table

# SECTION - Includes

include("init.jl")
include("check.jl")
include("alloc.jl")
# include("benchmarks.jl")
include("utils.jl")

end
