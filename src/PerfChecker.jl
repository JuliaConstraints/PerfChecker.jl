module PerfChecker

# SECTION - Imports
using Coverage
using CSV
using DataFrames
using Distributed
using Pkg
using PrettyTables
using Profile
using Random

# SECTION - Exports
export alloc_check
# export Pkg

# SECTION - Includes
include("allocations.jl")

end
