@testset "PatternFolds.jl" begin
    d = Dict(
        :targets => ["PatternFolds"], :path => @__DIR__, :tags => [:patterns, :intervals],
        :pkgs => ("PatternFolds", :custom, [v"0.2.1", v"0.2.4"], true))

    x = @check :alloc d begin
        using PatternFolds
    end begin
        itv = Interval{Open, Closed}(0.0, 1.0)
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

    d2 = Dict(:path => @__DIR__, :evals => 1, :samples => 100,
        :seconds => 100, :tags => [:patterns, :intervals],
        :pkgs => (
            "PatternFolds", :custom, [v"0.2.1", v"0.2.4"], true),
        :devops => "PatternFolds")

    x2 = @check :benchmark d2 begin
        using PatternFolds
    end begin
        # Intervals
        itv = Interval{Open, Closed}(0.0, 1.0)
        i = IntervalsFold(itv, 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # rand(i, 1000)

        # Vectors
        vf = make_vector_fold([0, 1], 2, 1000)
        # @info "Checking VectorFold" vf pattern(vf) gap(vf) folds(vf) length(vf)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        rand(vf, 1000)

        return nothing
    end

    @info x2

    d3 = Dict(:path => @__DIR__, :evals => 1, :samples => 100,
        :seconds => 100, :tags => [:patterns, :intervals],
        :pkgs => (
            "PatternFolds", :custom, [v"0.2.1", v"0.2.4"], true),
        :devops => "PatternFolds")

    x3 = @check :chairmark d3 begin
        using PatternFolds
    end begin
        # Intervals
        itv = Interval{Open, Closed}(0.0, 1.0)
        i = IntervalsFold(itv, 2.0, 1000)

        unfold(i)
        collect(i)
        reverse(collect(i))

        # rand(i, 1000)

        # Vectors
        vf = make_vector_fold([0, 1], 2, 1000)
        # @info "Checking VectorFold" vf pattern(vf) gap(vf) folds(vf) length(vf)

        unfold(vf)
        collect(vf)
        reverse(collect(vf))

        rand(vf, 1000)

        return nothing
    end

    @info x3
end
