function PerfChecker.default_options(::Val{:benchmark})
    return Dict(
        :threads => 1,
        :track => "none",
        :samples => BenchmarkTools.DEFAULT_PARAMETERS.samples,
        :seconds => BenchmarkTools.DEFAULT_PARAMETERS.seconds,
        :evals => BenchmarkTools.DEFAULT_PARAMETERS.evals,
        :overhead => BenchmarkTools.DEFAULT_PARAMETERS.overhead,
        :gctrial => BenchmarkTools.DEFAULT_PARAMETERS.gctrial,
        :gcsample => BenchmarkTools.DEFAULT_PARAMETERS.gcsample,
        :time_tolerance => BenchmarkTools.DEFAULT_PARAMETERS.time_tolerance,
        :memory_tolerance => BenchmarkTools.DEFAULT_PARAMETERS.memory_tolerance
    )
end

PerfChecker.prep(::Dict, block::Expr, ::Val{:benchmark}) = quote
    d = $d
    using BenchmarkTools
    @benchmark $block samples=d[:samples] seconds=d[:seconds] evals=d[:evals] overhead=d[:overhead] gctrial=d[:gctrial] gcsample=d[:gcsample] time_tolerance=g[:time_tolerance] memory_tolerance=g[:memory_tolerance]
end

PerfChecker.post(d::Dict, ::Val{:benchmark}) = d[:prep_result]

function bench_table(bench)
    ti = bench.times
    l = length(ti)
    return Table(times=ti, gctimes=bench.gctimes, memory=fill(bench.memory, l), allocs=fill(bench.allocs, l))
end
