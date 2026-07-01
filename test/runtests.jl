using Test

@testset "Package tests: PerfChecker" begin
    include("Aqua.jl")

    @testset "Other Packages" begin
        using BenchmarkTools
        using Chairmarks
        using PerfChecker
        import Pkg

        @testset "Config normalization" begin
            cfg = PerfChecker.normalize_config(:benchmark,
                Dict(:path => @__DIR__, :tags => [:unit], :threads => 1))
            @test cfg.backend == :benchmark
            @test cfg.tags == [:unit]
            @test cfg.threads == 1
            @test cfg.path == abspath(@__DIR__)
            @test_throws ArgumentError PerfChecker.normalize_config(:benchmark, Dict())

            pcfg = PerfConfig(:benchmark; path = @__DIR__, tags = [:ux], samples = 1)
            @test Dict(pcfg)[:samples] == 1
            @test PerfChecker.normalize_config(pcfg).backend == :benchmark
            @test (@macroexpand @check pcfg begin
                nothing
            end begin
                nothing
            end) isa Expr
            @test_throws ArgumentError PerfChecker.normalize_config(:alloc, pcfg)
            @test_throws ArgumentError PerfConfig(:benchmark, Dict("path" => @__DIR__))
        end

        @testset "Version selection" begin
            _, versions = PerfChecker.get_versions(
                ("PatternFolds", :custom, [v"0.2.1", v"0.2.4"], true))
            @test versions == [v"0.2.1", v"0.2.4"]
        end

        @testset "REPL and Pluto helpers" begin
            result = PerfChecker.CheckerResult(
                [PerfChecker.Table(times = [3.0, 1.0], bytes_or_memory = [20, 10],
                    allocs = [2, 1])],
                nothing,
                [:unit],
                [Pkg.Types.PackageSpec(name = "Example", version = v"1.2.3")])
            summary = summary_table(result)
            @test summary.package[1] == "Example"
            @test summary.version[1] == "1.2.3"
            @test summary.min_time[1] == 1.0
            @test summary.max_memory[1] == 20.0

            mktempdir() do dir
                perfdir = joinpath(dir, "perf")
                paths = perf_setup(; dir = perfdir, kinds = (:benchmark, :pluto))
                @test length(paths) == 2
                @test all(isfile, paths)
                @test occursin("PerfConfig(:benchmark", read(paths[1], String))
                @test occursin("Pluto.jl", read(paths[2], String))
                @test_throws ArgumentError write_template(:benchmark; path = paths[1])
                @test write_template(:benchmark; path = paths[1], force = true) == paths[1]
                @test_throws ArgumentError write_template(:unknown; path = joinpath(dir, "x.jl"))
            end
        end

        @testset "Allocation cleanup" begin
            mktempdir() do dir
                memfile = joinpath(dir, "dummy.jl.123.mem")
                write(memfile, "1 1\n")
                @test isfile(memfile)
                PerfChecker.rm_malloc_files([dir])
                @test !isfile(memfile)
            end
        end

        include("pattern_folds.jl")

        @test isempty(PerfChecker.find_malloc_files([joinpath(dirname(@__DIR__), "src")]))
    end

    rm("metadata"; recursive = true, force = true)
    rm("output"; recursive = true, force = true)
end
