@testitem "Feature and software suites" tags=[:suites] begin
    using BenchmarkTools
    using DrWatson
    using HTTP
    using JSON
    using Makie
    using Oxygen
    using PerfChecker
    using Pluto
    using Supposition
    import Pkg

    mktempdir() do dir
        write(joinpath(dir, "Project.toml"), """
name = "Example"
uuid = "7876af07-990d-454c-bd7d-19f24a2d73b8"
version = "0.2.0"
""")
        always_case = joinpath(dir, "always.jl")
        recent_case = joinpath(dir, "recent.jl")
        write(always_case, "perf_workload(state) = sum(1:10)\n")
        write(recent_case, "perf_workload(state) = sum(1:20)\n")

        always = FeatureSpec(:always;
            entrypoint = always_case,
            options = Dict(:samples => 1, :seconds => 0.01))
        recent = FeatureSpec(:recent;
            entrypoint = recent_case, since = v"0.2.0",
            comparison_key = "recent/v1",
            options = Dict(:samples => 1, :seconds => 0.01))
        package = PackageSuite("Example";
            environment = dir, source = dir, versions = :all,
            features = [always, recent])
        software = SoftwareSuite(:example, [package]; description = "Example surface")
        provider(_) = [v"0.1.0", v"0.2.0"]

        plan = plan_suite(software; profile = :historical, version_provider = provider)
        @test length(plan.runs) == 6
        @test count(run -> run.planned_status === :unavailable, plan.runs) == 1
        @test any(run -> run.target.label == "dev@0.2.0", plan.runs)
        @test any(run -> run.comparison_key == "recent/v1", plan.runs)

        executed = PlannedFeatureRun[]
        function fake_runner(planned, config, setup, workload)
            push!(executed, planned)
            return PerfChecker.CheckerResult(
                [PerfChecker.Table(times = [1.0], gctimes = [0.0],
                    bytes_or_memory = [8], memory = [8], allocs = [1])],
                nothing, [:suite],
                [Pkg.Types.PackageSpec(name = "Example", version = v"0.2.0")])
        end

        result = run_suite(plan; executor = fake_runner)
        @test suite_passed(result)
        @test count(run -> run.status === :pass, result.runs) == 5
        @test count(run -> run.status === :unavailable, result.runs) == 1
        @test length(executed) == 5

        job = launch_suite(plan; executor = fake_runner)
        async_result = wait_suite(job)
        @test suite_job_status(job) == :complete
        @test suite_job_dict(job)["result"]["passed"]
        @test suite_passed(async_result)

        summary = suite_summary(result)
        @test length(summary) == 6
        @test Set(summary.status) == Set(["pass", "unavailable"])

        reports = write_suite_reports(result, joinpath(dir, "reports"))
        @test length(reports) == 3
        @test all(isfile, reports)
        parsed = JSON.parsefile(joinpath(dir, "reports", "suite-result.json"))
        @test parsed["schema_version"] == "perfchecker-suite-result/1"
        @test parsed["passed"]
        @test occursin("<testsuite", read(joinpath(dir, "reports", "suite-junit.xml"), String))

        notebook = write_suite_notebook(joinpath(dir, "dashboard.jl"))
        @test isfile(notebook)
        notebook_source = read(notebook, String)
        @test occursin("suite-result.json", notebook_source)
        @test !occursin("@testitem", notebook_source)

        launcher = write_suite_notebook(joinpath(dir, "launcher.jl");
            suite_path = "suite.jl", factory = :example_suite)
        launcher_source = read(launcher, String)
        @test occursin("launch_suite", launcher_source)
        @test occursin("example_suite", launcher_source)

        definition = joinpath(dir, "suite-definition.jl")
        write(definition, """
using PerfChecker
function build_suite()
    feature = FeatureSpec(:loaded; entrypoint = $(repr(always_case)))
    package = PackageSuite("Example"; environment = $(repr(dir)),
        source = $(repr(dir)), versions = VersionNumber[v\"0.2.0\"],
        include_dev = false, features = [feature])
    SoftwareSuite(:loaded, [package])
end
""")
        loaded = load_software_suite(definition)
        @test loaded.id === :loaded
        loaded_result = run_suite_file(definition; profile = :historical,
            reports = joinpath(dir, "loaded-reports"), executor = fake_runner)
        @test suite_passed(loaded_result)
        @test isfile(joinpath(dir, "loaded-reports", "suite-result.json"))

        corpus_path = write_property_corpus(joinpath(dir, "corpus.json"),
            Any[Dict("value" => 1), Dict("value" => 2)]; metadata = Dict(:seed => 7))
        corpus = read_property_corpus(corpus_path)
        @test corpus["count"] == 2
        @test corpus["metadata"]["seed"] == 7
        @test_throws ArgumentError write_property_corpus(corpus_path, Any[])

        generated_path = freeze_supposition_corpus(joinpath(dir, "generated.json"),
            Supposition.Data.Integers(0, 10); count = 4)
        generated = read_property_corpus(generated_path)
        @test generated["producer"] == "Supposition.jl"
        @test length(generated["cases"]) == 4

        @testset "DrWatson extension" begin
            parameters = drwatson_parameters(plan)
            @test length(parameters) == 6
            ready = first(run for run in plan.runs if run.planned_status === :ready)
            @test endswith(drwatson_savename(ready), ".jld2")

            data, path = drwatson_produce_or_load(
                Dict("case" => "one"); directory = joinpath(dir, "drwatson"), tag = false) do p
                Dict("case" => p["case"], "value" => 1)
            end
            @test data["value"] == 1
            @test isfile(path)
        end

        @testset "Oxygen extension" begin
            Oxygen.resetstate()
            register_oxygen_routes!(result; prefix = "/test/perfchecker/v1")
            response = Oxygen.internalrequest(
                HTTP.Request("GET", "/test/perfchecker/v1/suite"))
            @test response.status == 200
            body = JSON.parse(String(response.body))
            @test body["suite"] == "example"
            @test length(body["runs"]) == 6
            Oxygen.resetstate()

            register_oxygen_routes!(software; prefix = "/test/perfchecker/jobs",
                profile = :historical, version_provider = provider,
                executor = fake_runner)
            launch_response = Oxygen.internalrequest(
                HTTP.Request("POST", "/test/perfchecker/jobs/jobs"))
            @test launch_response.status == 200
            launch_body = JSON.parse(String(launch_response.body))
            @test haskey(launch_body, "job_id")
            sleep(0.05)
            status_response = Oxygen.internalrequest(HTTP.Request(
                "GET", "/test/perfchecker/jobs/jobs?id=$(launch_body["job_id"])"))
            @test status_response.status == 200
            status_body = JSON.parse(String(status_response.body))
            @test status_body["status"] == "complete"
            Oxygen.resetstate()
        end

        @testset "Pluto and Makie extensions" begin
            @test hasmethod(launch_pluto_dashboard, Tuple{String})

            figure = suite_dashboard(result)
            @test figure isa Makie.Figure
            figure_from_job = suite_dashboard(launch_suite(plan; executor = fake_runner))
            @test figure_from_job isa Makie.Figure
            figure_from_suite = suite_dashboard(software; profile = :historical,
                version_provider = provider, executor = fake_runner)
            @test figure_from_suite isa Makie.Figure
        end
    end
end
