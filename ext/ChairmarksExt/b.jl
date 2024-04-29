function PerfChecker.default_options(::Val{:chairmark})
    return Dict(
        :threads => 1,
        :track => "none",
        :init => nothing,
        :setup => nothing,
        :f => nothing,
        :teardown => nothing,
        :kwargs => ()
    )
end

function PerfChecker.check(d::Dict, block::Expr, ::Val{:chairmark})
    if d[:f] == nothing
        d[:f] = @eval () -> $block
    end
    quote
        d = $d
        using Chairmarks
        return Chairmarks.benchmark(d[:init], d[:setup], d[:f], d[:teardown]; d[:kwargs]...)
    end
end

PerfChecker.prep(::Dict, block::Expr, ::Val{:chairmark}) = quote
    $block
    nothing
end

PerfChecker.post(d::Dict, ::Val{:chairmark}) = d[:check_result]
#=
function PerfChecker.to_table(bench::BenchmarkTools.Trial)
    ti = bench.times
    l = length(ti)
    return Table(times=ti, gctimes=bench.gctimes, memory=fill(bench.memory, l), allocs=fill(bench.allocs, l))
end
=#
