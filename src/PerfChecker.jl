module PerfChecker

# SECTION - Imports
#using DataFrames
using LibGit2
using OrderedCollections
using Pkg
using Profile
using Random
import TypedTables: Table
import Distributed: remotecall_fetch, addprocs, rmprocs
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo

# SECTION - Exports
export alloc_check
export alloc_plot
export store_benchmark
export @check
export to_table

# SECTION - Includes

include("check.jl")
include("alloc.jl")
#include("benchmarks.jl")
#include("utils.jl")

end
