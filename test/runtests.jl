using Test

@testset "Package tests: PerfChecker" begin
    include("Aqua.jl")

    @testset "Other Packages" begin
        using BenchmarkTools
        using Distributed
        using PerfChecker

        # include("compositional_networks.jl")
        include("pattern_folds.jl")
    end
end
