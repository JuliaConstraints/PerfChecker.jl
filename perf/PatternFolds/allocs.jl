using PerfChecker
using PrettyTables

d = Dict(:targets => ["PatternFolds"], :path => @__DIR__, :tags => [:patterns, :intervals], :pkgs => ("PatternFolds", :custom, [v"0.2.3", v"0.2.2"], true))

x = @check :alloc d begin

    using PatternFolds
    end begin
    itv = Interval{Open,Closed}(0.0, 1.0)
    i = IntervalsFold(itv, 2.0, 1000)

    @info "Checking IntervalsFold" i pattern(i) gap(i) folds(i) size(i) length(i)

    unfold(i)
    collect(i)
    reverse(collect(i))

    # Vectors
    vf = make_vector_fold([0, 1], 2, 1000)
    @info "Checking VectorFold" vf pattern(vf) gap(vf) folds(vf) length(vf)

    unfold(vf)
    collect(vf)
    reverse(collect(vf))

    rand(vf, 1000)
end

@info x
