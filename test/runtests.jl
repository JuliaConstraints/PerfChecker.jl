using Test

@testset "Package tests: PerfChecker" begin
    include("Aqua.jl")

    @testset "Other Packages" begin
        using BenchmarkTools
        using Chairmarks
        using PerfChecker

        include("pattern_folds.jl")
    end

    rm("metadata"; recursive = true)
    rm("output"; recursive = true)
end
