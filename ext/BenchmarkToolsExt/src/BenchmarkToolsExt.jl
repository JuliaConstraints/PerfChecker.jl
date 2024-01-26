module BenchmarkToolsExt

using BenchmarkTools
using PerfChecker
PerfChecker.default_options(s::String) = "Hello"
@info PerfChecker.default_options("Helalo")
import TypedTables: Table

export bench_table
end
