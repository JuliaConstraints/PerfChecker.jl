using PerfChecker

d = Dict(:targets => ["GLM"],
    :path => @__DIR__,
    :pkgs => ("GLM",
        :custom,
        [
            v"1.3.9", v"1.3.10", v"1.3.11", v"1.4.0",
            v"1.5.0", v"1.6.0", v"1.7.0", v"1.8.0",
            v"1.9.0"],
        true),
    :tags => [:bernoulli])

x = @check :alloc d begin
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
