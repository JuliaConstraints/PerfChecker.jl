using PatternFolds

@testset "PatternFolds.jl" begin
    @check :alloc Dict(:target => ["PatternFolds"], :path => pwd()) begin
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
end
#=
target = PatternFolds

function bench() # 0.2.x
    # Intervals
    itv = Interval{Open,Closed}(0.0, 1.0)
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

t = @benchmark bench() evals = 1 samples = 1000 seconds = 3600

# Actual call to PerfChecker
store_benchmark(t, target; path=@__DIR__)
=#
