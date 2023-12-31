using PerfChecker, PrettyTables

x = @check :alloc Dict(:targets => ["GLM"], :path => @__DIR__) begin
    using GLM, Random, StatsModels
    end begin
    n = 2_500_000
    rng = Random.MersenneTwister(1234321)
    tbl = (
        x1=randn(rng, n),
        x2=Random.randexp(rng, n),
        ss=rand(rng, string.(50:99), n),
        y=zeros(n),
    )
    f = @formula(y ~ 1 + x1 + x2 + ss)
    f = apply_schema(f, schema(f, tbl))
    resp, pred = modelcols(f, tbl)
    B = randn(rng, size(pred, 2))
    B[1] = 0.5
    logistic(x::Real) = inv(1 + exp(-x))
    resp .= rand(rng, n) .< logistic.(pred * B)
    glm(pred, resp, Bernoulli())
end


pretty_table(x |> to_table)
