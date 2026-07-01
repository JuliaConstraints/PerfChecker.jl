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

        @testset "Cache identity" begin
            mktempdir() do dir
                cfg = PerfChecker.normalize_config(:benchmark,
                    Dict(:path => dir, :tags => [:cache], :threads => 1, :samples => 1))
                block1 = :(using Random)
                block2 = :(sum(1:10))
                hwinfo = PerfChecker.HwInfo()
                pkg = "Example"
                version = v"1.2.3"

                run = PerfChecker.run_metadata(cfg, pkg, version, block1, block2, hwinfo)
                out = PerfChecker.output_path(cfg.path, run.result_uuid)
                PerfChecker.table_to_csv(
                    PerfChecker.Table(times = [1.0], gctimes = [0.0],
                        bytes_or_memory = [0], memory = [0], allocs = [0]),
                    out)
                PerfChecker.write_run_metadata(PerfChecker.metadata_path(cfg.path), run)

                @test PerfChecker.metadata_has_result(
                    PerfChecker.metadata_path(cfg.path), run.result_uuid)
                @test PerfChecker.cached_output_path(cfg, pkg, version, block1, block2,
                    hwinfo) == out

                tag_cfg = PerfChecker.normalize_config(:benchmark,
                    Dict(:path => dir, :tags => [:other], :threads => 1, :samples => 1))
                opt_cfg = PerfChecker.normalize_config(:benchmark,
                    Dict(:path => dir, :tags => [:cache], :threads => 1, :samples => 2))
                other_hw = PerfChecker.HwInfo(
                    hwinfo.cpus, "other-machine", hwinfo.word, hwinfo.simdbytes,
                    hwinfo.corecount)

                @test isnothing(PerfChecker.cached_output_path(
                    tag_cfg, pkg, version, block1, block2, hwinfo))
                @test isnothing(PerfChecker.cached_output_path(
                    opt_cfg, pkg, version, block1, block2, hwinfo))
                @test isnothing(PerfChecker.cached_output_path(
                    cfg, pkg, version, block1, :(sum(1:11)), hwinfo))
                @test isnothing(PerfChecker.cached_output_path(
                    cfg, pkg, version, block1, block2, other_hw))
            end
        end

        @testset "Legacy cache metadata" begin
            mktempdir() do dir
                cfg = PerfChecker.normalize_config(:benchmark,
                    Dict(:path => dir, :tags => [:legacy], :threads => 1))
                pkg = "Example"
                version = v"1.2.3"
                legacy_uuid = PerfChecker.file_uuid(cfg.backend, pkg, version, cfg.tags)
                legacy_out = PerfChecker.output_path(cfg.path, legacy_uuid)
                PerfChecker.table_to_csv(
                    PerfChecker.Table(times = [1.0], gctimes = [0.0],
                        bytes_or_memory = [0], memory = [0], allocs = [0]),
                    legacy_out)
                PerfChecker.check_to_metadata_csv(
                    cfg.backend, pkg, version, cfg.tags;
                    metadata = PerfChecker.metadata_path(cfg.path))

                @test PerfChecker.cached_output_path(
                    cfg, pkg, version, :(nothing), :(nothing), PerfChecker.HwInfo()) ==
                      legacy_out
            end
        end

        include("pattern_folds.jl")

        @test isempty(PerfChecker.find_malloc_files([joinpath(dirname(@__DIR__), "src")]))
    end

    rm("metadata"; recursive = true, force = true)
    rm("output"; recursive = true, force = true)
end
