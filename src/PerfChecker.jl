module PerfChecker

# imports
using Coverage
using CSV
using DataFrames
using Distributed
using PrettyTables
using Profile

# exports
export alloc_set

# includes
include("alloc.jl")

end
