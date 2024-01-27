using BenchmarkTools
using Distributed
using PerfChecker
using PrettyTables
using Test

import CompatHelperLocal

CompatHelperLocal.@check()

# include("compositional_networks.jl")

include("pattern_folds.jl")
