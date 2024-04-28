function PerfChecker.default_options(::Val{:chairb})
    return Dict(
        :threads => 1,
        :track => "none",
    )
end

PerfChecker.check(d::Dict, block::Expr, ::Val{:chairb}) = quote
    d = $d
    using Chairmark
    return @benchmark $block samples=d[:samples] seconds=d[:seconds] evals=d[:evals] overhead=d[:overhead] gctrial=d[:gctrial] gcsample=d[:gcsample] time_tolerance=d[:time_tolerance] memory_tolerance=d[:memory_tolerance]
end

PerfChecker.prep(::Dict, block::Expr, ::Val{:chairb}) = quote
    $block
    nothing
end

PerfChecker.post(d::Dict, ::Val{:chairb}) = d[:check_result]

function PerfChecker.to_table(bench::BenchmarkTools.Trial)
    ti = bench.times
    l = length(ti)
    return Table(times=ti, gctimes=bench.gctimes, memory=fill(bench.memory, l), allocs=fill(bench.allocs, l))
end
