function PerfChecker.default_options(::Val{:chairmark})
    return Dict(
        :threads => 1,
        :track => "none",
        :evals => nothing,
        :seconds => 1,
        :samples => nothing,
        :gc => true
    )
end

PerfChecker.initpkgs(::Val{:chairmark}) = quote
    using Chairmarks
end

function PerfChecker.check(d::Dict, block::Expr, ::Val{:chairmark})
    quote
        d = $d
        return @be $block evals=d[:evals] seconds=d[:seconds] samples=d[:samples] gc=d[:gc]
    end
end

PerfChecker.prep(::Dict, block::Expr, ::Val{:chairmark}) = quote
    $block
    nothing
end

PerfChecker.post(d::Dict, ::Val{:chairmark}) = d[:check_result]

function PerfChecker.to_table(chair::Chairmarks.Benchmark)
    l = length(chair.samples)
    times = [chair.samples[i].time for i in 1:l]
    gctimes = [chair.samples[i].gc_fraction for i in 1:l]
    bytes = [chair.samples[i].bytes for i in 1:l]
    allocs = [chair.samples[i].allocs for i in 1:l]
    return Table(times = times, gctimes = gctimes, bytes = bytes, allocs = allocs)
end
