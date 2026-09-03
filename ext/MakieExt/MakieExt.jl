module MakieExt

using Makie
using TypedTables
using PerfChecker

include("plotutils.jl")
include("allocs.jl")
include("bench.jl")
include("chair.jl")
include("suite.jl")
include("performance.jl")

end
