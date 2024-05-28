using PerfChecker, CairoMakie

d = Dict(:targets => ["PatternFolds"], :path => @__DIR__, :tags => [:patterns, :intervals],
    :pkgs => (
        "PatternFolds", :custom, [v"0.2.0", v"0.2.1", v"0.2.2", v"0.2.3", v"0.2.4"], true))

x = @check :alloc d begin
    using PatternFolds
end begin
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
end

@info x

mkpath(joinpath(@__DIR__, "visuals"))

c = checkres_to_scatterlines(x, Val(:alloc))
save(joinpath(@__DIR__, "visuals", "allocs_evolution.png"), c)

for (name, c2) in checkres_to_pie(x, Val(:alloc))
    save(joinpath(@__DIR__, "visuals", "allocs_pie_$name.png"), c2)
end
