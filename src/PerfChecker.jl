module PerfChecker

# SECTION - Imports
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

# SECTION - Exports
export alloc_check
export alloc_plot

# SECTION - Includes
include("allocations.jl")
include("utils.jl")

end
