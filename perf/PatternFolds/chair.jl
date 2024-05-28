using PerfChecker, Chairmarks

d = Dict(:path => @__DIR__, :evals => 1, :tags => [:patterns, :intervals],
    :pkgs => ("PatternFolds", :custom, [v"0.2.2", v"0.2.3", v"0.2.4"], true),
    :devops => "PatternFolds")

t = @check :chairmark d begin
    using PatternFolds
end begin
    # Intervals
    itv = Interval{Open, Closed}(0.0, 1.0)
    i = IntervalsFold(itv, 2.0, 1000)

    unfold(i)
    collect(i)
    reverse(collect(i))

    # Vectors
    vf = make_vector_fold([0, 1], 2, 1000)

    unfold(vf)
    collect(vf)
    reverse(collect(vf))

    rand(vf, 1000)

    return nothing
end

@info t
