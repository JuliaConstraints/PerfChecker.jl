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
    using SHA
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
        plan_payload = suite_plan_dict(plan)
        @test length(plan_payload["plan_revision"]) == 64
        @test length(unique(run["id"] for run in plan_payload["runs"])) == 6
        selected_ids = reverse([run["id"] for run in plan_payload["runs"][1:2]])
        selected = select_suite_plan(plan, selected_ids)
        @test planned_run_id.(selected.runs) == selected_ids
        @test_throws ArgumentError select_suite_plan(plan,
            [selected_ids[1], selected_ids[1]])
        @test_throws ArgumentError select_suite_plan(plan, ["unknown"])
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
        @test length(reports) == 7
        @test all(ispath, reports)
        parsed = JSON.parsefile(joinpath(dir, "reports", "suite-result.json");
            use_mmap = false)
        @test parsed["schema_version"] == "perfchecker-suite-result/1"
        @test parsed["passed"]
        @test occursin("<testsuite", read(joinpath(dir, "reports", "suite-junit.xml"), String))
        bundle_path = only(filter(isdir, reports))
        bundle = read_run_bundle(bundle_path)
        @test bundle_passed(bundle)
        @test !isempty(bundle.observations)
        @test isfile(joinpath(dir, "reports", "version-series.json"))
        @test isfile(joinpath(dir, "reports", "version-comparison.json"))
        @test isfile(joinpath(dir, "reports", "version-comparison.md"))

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
                executor = fake_runner, reports_root = joinpath(dir, "studio-results"))
            plan_response = Oxygen.internalrequest(
                HTTP.Request("GET", "/test/perfchecker/jobs/suite-plan?profile=historical"))
            @test plan_response.status == 200
            plan_body = JSON.parse(String(plan_response.body))
            selected_ids = [run["id"] for run in plan_body["runs"]][1:2]
            launch_payload = Dict(
                "profile" => "historical",
                "plan_revision" => plan_body["plan_revision"],
                "selected_run_ids" => selected_ids,
                "overrides" => Dict("samples" => 3, "seconds" => 0.01),
                "relative_limits" => Dict("benchmark.time" => 0.10),
                "min_samples" => 1)
            launch_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/jobs/jobs", ["Content-Type" => "application/json"],
                JSON.json(launch_payload)))
            @test launch_response.status == 202
            launch_body = JSON.parse(String(launch_response.body))
            @test haskey(launch_body, "job_id")
            status_response = nothing
            status_body = nothing
            for _ in 1:100
                status_response = Oxygen.internalrequest(HTTP.Request(
                    "GET", "/test/perfchecker/jobs/jobs?id=$(launch_body["job_id"])"))
                status_body = JSON.parse(String(status_response.body))
                status_body["state"] in ("complete", "failed") && break
                sleep(0.02)
            end
            @test status_response.status == 200
            @test status_body["state"] == "complete"
            @test status_body["run_count"] == 2
            @test isfile(joinpath(dir, "studio-results", "jobs",
                launch_body["job_id"], "version-comparison.json"))

            stale_payload = merge(launch_payload, Dict("plan_revision" => "stale"))
            stale_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/jobs/jobs", ["Content-Type" => "application/json"],
                JSON.json(stale_payload)))
            @test stale_response.status == 409
            invalid_payload = merge(launch_payload,
                Dict("overrides" => Dict("arbitrary_code" => "no")))
            invalid_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/jobs/jobs", ["Content-Type" => "application/json"],
                JSON.json(invalid_payload)))
            @test invalid_response.status == 400
            @test Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/jobs/assets/perfchecker-studio.css")).status == 200
            @test Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/jobs/assets/perfchecker-studio.js")).status == 200
            Oxygen.resetstate()

            token = "test-personal-access-token"
            authenticate = studio_token_authenticator(Dict(
                bytes2hex(sha256(token)) => Dict("id" => "developer-1",
                    "name" => "Package developer", "roles" => ["runner", "agent"])))
            register_oxygen_routes!(software; prefix = "/test/perfchecker/hosted",
                profile = :quick, version_provider = provider, executor = fake_runner,
                reports_root = joinpath(dir, "hosted-results"),
                authenticator = authenticate)
            @test Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/hosted/")).status == 200
            @test Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/hosted/suite-plan")).status == 401
            auth_headers = ["Authorization" => "Bearer $token"]
            hosted_plan = Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/hosted/suite-plan", auth_headers))
            @test hosted_plan.status == 200
            hosted_identity = Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/hosted/me", auth_headers))
            @test JSON.parse(String(hosted_identity.body))["identity"]["id"] ==
                  "developer-1"

            hosted_plan_body = JSON.parse(String(hosted_plan.body))
            remote_ids = [run["id"] for run in hosted_plan_body["runs"]][1:2]
            remote_launch = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/hosted/jobs",
                [auth_headers; "Content-Type" => "application/json"], JSON.json(Dict(
                    "profile" => "quick",
                    "plan_revision" => hosted_plan_body["plan_revision"],
                    "selected_run_ids" => remote_ids,
                    "execution_target" => "agent:worker-1"))))
            @test remote_launch.status == 202
            remote_job = JSON.parse(String(remote_launch.body))
            @test remote_job["state"] == "waiting_agent"
            claim = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/hosted/agents/claim",
                [auth_headers; "Content-Type" => "application/json"],
                JSON.json(Dict("agent_id" => "worker-1"))))
            @test claim.status == 200
            claim_body = JSON.parse(String(claim.body))
            local_remote_plan = select_suite_plan(plan_suite(software;
                profile = :quick, version_provider = provider), remote_ids)
            remote_result = run_suite(local_remote_plan; executor = fake_runner,
                strict = false)
            remote_bundle = PerfChecker._suite_run_bundle(remote_result)
            completion = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/hosted/agents/complete",
                [auth_headers; "Content-Type" => "application/json"], JSON.json(Dict(
                    "agent_id" => "worker-1", "job_id" => claim_body["job_id"],
                    "bundle" => bundle_dict(remote_bundle)))))
            @test completion.status == 200
            @test JSON.parse(String(completion.body))["state"] == "complete"
            Oxygen.resetstate()

            register_oxygen_routes!(bundle; prefix = "/test/perfchecker/bundle")
            bundle_response = Oxygen.internalrequest(
                HTTP.Request("GET", "/test/perfchecker/bundle/observations"))
            @test bundle_response.status == 200
            @test length(JSON.parse(String(bundle_response.body))) ==
                  length(bundle.observations)
            Oxygen.resetstate()

            store = joinpath(dir, "reports", "bundles")
            register_oxygen_routes!(store; prefix = "/test/perfchecker/store")
            page_response = Oxygen.internalrequest(
                HTTP.Request("GET", "/test/perfchecker/store/"))
            @test page_response.status == 200
            @test occursin("Performance Studio", String(page_response.body))
            store_response = Oxygen.internalrequest(
                HTTP.Request("GET", "/test/perfchecker/store/runs"))
            @test store_response.status == 200
            @test only(JSON.parse(String(store_response.body)))["run_id"] ==
                  bundle.manifest["run_id"]
            @test !haskey(only(JSON.parse(String(store_response.body))), "bundle_path")
            Oxygen.resetstate()

            ingest_store = joinpath(dir, "ingested-bundles")
            register_oxygen_routes!(ingest_store;
                prefix = "/test/perfchecker/ingest", allow_ingest = true)
            provider_payload = Dict(
                "schema_version" => "perfchecker-provider-result/1",
                "suite" => "mixed", "case_id" => "external",
                "runtime" => Dict("language" => "python"),
                "measurement_definitions" => [Dict("id" => "custom.work/v1",
                    "metric" => "custom.work", "unit" => "1")],
                "observations" => [Dict("metric" => "custom.work", "value" => 1,
                    "unit" => "1", "measurement_definition" => "custom.work/v1")])
            ingest_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/ingest/ingest", ["Content-Type" => "application/json"],
                JSON.json(provider_payload)))
            @test ingest_response.status == 201
            @test length(list_run_bundles(ingest_store)) == 1
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
