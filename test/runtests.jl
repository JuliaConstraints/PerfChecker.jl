using Test

@testset "Package tests: PerfChecker" begin
    include("Aqua.jl")

    @testset "Other Packages" begin
        using BenchmarkTools
        using PerfChecker

        # include("compositional_networks.jl")
        include("pattern_folds.jl")
    end
end
