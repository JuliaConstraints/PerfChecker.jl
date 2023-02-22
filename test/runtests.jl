using BenchmarkTools
using PerfChecker
using Test

import CompatHelperLocal

CompatHelperLocal.@check()

# include("compositional_networks.jl")

include("pattern_folds.jl")
