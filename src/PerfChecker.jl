module PerfChecker

# SECTION - Imports
using Coverage
using CSV
using DataFrames
using Distributed
using LibGit2
using Pkg
using PrettyTables
using Profile
using Random

# SECTION - Exports
export alloc_check
# export Pkg

# SECTION - Includes
include("allocations.jl")
include("utils.jl")

end
