module BenchmarkToolsExt

using BenchmarkTools
import TypedTables: Table

include("benchmark.jl")

export bench_table
end
