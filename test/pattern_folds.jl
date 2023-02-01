using PatternFolds

@testset "PatternFolds.jl" begin
    # Title of the alloc check (for logging purpose)
    title = "Basic intervals and vectors folds operation"

    # Dependencies needed to execute pre_alloc and alloc
    dependencies = [PatternFolds]

    # Target of the alloc check
    targets = [PatternFolds]

    function alloc() # 0.2.x
        # Intervals
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

        return nothing
    end

    # Actual call to PerfChecker
    alloc_check(title, dependencies, targets, alloc, alloc; path=@__DIR__)

end

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
