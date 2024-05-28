using PerfChecker, BenchmarkTools, CairoMakie

d = Dict(:targets => ["GLM"],
    :path => @__DIR__, :evals => 1, :samples => 100, :seconds => 100,
    :pkgs => ("GLM",
        :custom,
        [
            v"1.3.9", v"1.3.10", v"1.3.11", v"1.4.0",
            v"1.5.0", v"1.6.0", v"1.7.0", v"1.8.0",
            v"1.9.0"],
        true),
    :tags => [:bernoulli])

x = @check :benchmark d begin
    using GLM, Random, StatsModels
end begin
    n = 2_500_000
    rng = Random.MersenneTwister(1234321)
    tbl = (
        x1 = randn(rng, n),
        x2 = Random.randexp(rng, n),
        ss = rand(rng, string.(50:99), n),
        y = zeros(n)
    )
    f = @formula(y~1 + x1 + x2 + ss)
    f = apply_schema(f, schema(f, tbl))
    resp, pred = modelcols(f, tbl)
    B = randn(rng, size(pred, 2))
    B[1] = 0.5
    logistic(x::Real) = inv(1 + exp(-x))
    resp .= rand(rng, n) .< logistic.(pred * B)
    glm(pred, resp, Bernoulli())
end

@info x

mkpath(joinpath(@__DIR__, "visuals"))

c = checkres_to_scatterlines(x, Val(:benchmark))
save(joinpath(@__DIR__, "visuals", "bench_evolution.png"), c)

for kwarg in [:times, :gctimes, :memory, :allocs]
    c2 = checkres_to_boxplots(x, Val(:benchmark); kwarg)
    save(joinpath(@__DIR__, "visuals", "bench_boxplots_$kwarg.png"), c2)
end
