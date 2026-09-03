@testitem "Feature and software suites" tags=[:suites] begin
    using BenchmarkTools
    using DrWatson
    using Documenter
    using DocumenterVitepress
    using FlameGraphs
    using HTTP
    using JSON
    using Makie
    using Oxygen
    using PProf
    using PerfChecker
    using Pluto
    using PropCheck
    using Supposition
    using UnicodePlots
    using WGLMakie
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
            workload = :recent_business_feature,
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
        @test plan_payload["runs"][1]["entrypoint"] == always_case
        @test any(run -> run["workload"] == "recent_business_feature",
            plan_payload["runs"])
        @test workload_id(recent) === :recent_business_feature
        @test length(unique(run["id"] for run in plan_payload["runs"])) == 6
        selected_ids = reverse([run["id"] for run in plan_payload["runs"][1:2]])
        selected = select_suite_plan(plan, selected_ids)
        @test planned_run_id.(selected.runs) == selected_ids
        selected_from_ui = select_suite_plan(plan,
            Dict{String, Any}(
                "schema_version" => "perfchecker-ui-config/1",
                "selection" => Dict("run_ids" => selected_ids)))
        @test planned_run_id.(selected_from_ui.runs) == selected_ids
        @test_throws ArgumentError select_suite_plan(plan,
            [selected_ids[1], selected_ids[1]])
        @test_throws ArgumentError select_suite_plan(plan, ["unknown"])
        @test count(run -> run.planned_status === :unavailable, plan.runs) == 1
        @test any(run -> run.target.label == "dev@0.2.0", plan.runs)
        @test any(run -> run.comparison_key == "recent/v1", plan.runs)

        candidate = SuiteCandidate("branch-fast-parser", "feature/fast-parser";
            source = dir, compatibility_version = v"0.2.0")
        candidate_package = PackageSuite("Example";
            environment = dir, source = dir, versions = VersionNumber[],
            include_dev = false, candidates = [candidate], features = [always])
        candidate_plan = plan_suite(SoftwareSuite(:candidate, [candidate_package]);
            profile = :historical, version_provider = provider)
        candidate_run = only(candidate_plan.runs)
        @test candidate_run.target.kind === :candidate
        @test candidate_run.target.label == "branch-fast-parser"
        @test candidate_run.target.revision == "feature/fast-parser"
        candidate_payload = only(suite_plan_dict(candidate_plan)["runs"])
        @test candidate_payload["target_kind"] == "candidate"
        @test candidate_payload["target_revision"] == "feature/fast-parser"
        ui_target = Dict{String, Any}("package" => "Example",
            "label" => "ui-candidate", "revision" => "abc123",
            "source" => dir, "compatibility_version" => "0.2.0")
        ui_comparison = Dict{String, Any}("id" => "ui-comparison",
            "package" => "Example", "feature" => "always",
            "comparison_key" => "always", "baselines" => ["dev@0.2.0"],
            "candidates" => ["ui-candidate"], "aggregation" => "median")
        configuration = Dict{String, Any}("targets" => [ui_target],
            "comparisons" => [ui_comparison])
        requested_candidates = PerfChecker._requested_candidates(
            Dict{String, Vector{String}}(), configuration)
        @test only(requested_candidates["Example"]).revision == "abc123"
        @test only(PerfChecker._requested_comparisons(
            Dict{String, Vector{String}}(), configuration)).id == "ui-comparison"
        candidate_config = Ref{Any}(nothing)
        function fake_candidate_runner(planned, config, setup, workload)
            candidate_config[] = config
            return PerfChecker.CheckerResult(
                [PerfChecker.Table(times = [1.0], gctimes = [0.0],
                    bytes_or_memory = [8], memory = [8], allocs = [1])],
                nothing, [:candidate],
                [Pkg.Types.PackageSpec(name = "Example", version = v"0.2.0")])
        end
        candidate_result = run_suite(candidate_plan; executor = fake_candidate_runner)
        @test suite_passed(candidate_result)
        @test candidate_config[].options[:target_install] === :add
        @test candidate_config[].options[:devops].rev == "feature/fast-parser"

        future_runtime = FeatureSpec(:future_runtime; entrypoint = always_case,
            julia_since = v"999")
        runtime_package = PackageSuite("Example";
            environment = dir, source = dir, versions = [v"0.2.0"],
            include_dev = false, features = [future_runtime])
        runtime_plan = plan_suite(SoftwareSuite(:runtime_window, [runtime_package]);
            profile = :release, version_provider = provider)
        runtime_run = only(runtime_plan.runs)
        @test runtime_run.planned_status === :unavailable
        @test occursin("requires Julia >=999.0.0", runtime_run.reason)
        runtime_payload = only(suite_plan_dict(runtime_plan)["runs"])
        @test runtime_payload["julia_compatibility"]["since"] == "999.0.0"

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
        @test suite_job_progress(job)["completed"] == length(plan.runs)
        @test suite_job_progress(job)["percent"] == 100
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
        @test all(haskey(run, "workload") for run in parsed["runs"])
        @test occursin(
            "<testsuite", read(joinpath(dir, "reports", "suite-junit.xml"), String))
        bundle_path = only(filter(isdir, reports))
        bundle = read_run_bundle(bundle_path)
        @test bundle_passed(bundle)
        @test !isempty(bundle.observations)
        @test isfile(joinpath(dir, "reports", "version-series.json"))
        @test isfile(joinpath(dir, "reports", "version-comparison.json"))
        @test isfile(joinpath(dir, "reports", "version-comparison.md"))
        plots = plot_catalog(bundle)
        @test !isempty(plots)
        first_plot = performance_plot(bundle, first(plots)["id"])
        @test performance_figure(first_plot) isa Makie.Figure
        plot_html = performance_plot_html(first_plot)
        @test occursin("canvas", lowercase(plot_html))
        @test plot_html == performance_plot_html(first_plot)

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

        legacy_path = freeze_propcheck_corpus(joinpath(dir, "propcheck.json"),
            PropCheck.itype(Int8); count = 4, seed = 7)
        legacy = read_property_corpus(legacy_path)
        @test legacy["producer"] == "PropCheck.jl"
        @test length(legacy["cases"]) == 4

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
            studio_html = String(Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/jobs/")).body)
            @test occursin("version-min", studio_html)
            @test occursin("add-visible", studio_html)
            @test occursin("result-filter", studio_html)
            @test occursin("result-profile-filter", studio_html)
            @test occursin("result-sort", studio_html)
            @test occursin("plot-package-filter", studio_html)
            @test occursin("plot-metric-filter", studio_html)
            @test occursin("sandbox=\"allow-scripts\"", studio_html)
            state_file = joinpath(dir, "studio-results", "studio-state.json")
            @test isfile(state_file)
            @test any(job -> job["job_id"] == launch_body["job_id"],
                JSON.parsefile(state_file; use_mmap = false)["jobs"])
            Oxygen.resetstate()

            register_oxygen_routes!(software; prefix = "/test/perfchecker/recovered",
                profile = :historical, version_provider = provider,
                executor = fake_runner, reports_root = joinpath(dir, "studio-results"))
            recovered = JSON.parse(String(Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/recovered/jobs")).body))
            @test any(
                job -> job["job_id"] == launch_body["job_id"] &&
                       job["state"] == "complete", recovered)
            Oxygen.resetstate()

            token = "test-personal-access-token"
            authenticate = studio_token_authenticator(Dict(
                bytes2hex(sha256(token)) => Dict("id" => "developer-1",
                "name" => "Package developer", "roles" => ["runner", "agent"],
                "agent_ids" => ["worker-1"])))
            user_store = joinpath(dir, "studio-users.toml")
            write(user_store, """
[[users]]
id = "developer-1"
name = "Package developer"
roles = ["runner", "agent"]
agent_ids = ["worker-1"]
token_sha256 = "$(bytes2hex(sha256(token)))"
""")
            @test studio_token_authenticator(user_store)(token)["id"] == "developer-1"
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
            session_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/hosted/session", auth_headers))
            @test session_response.status == 200
            session_cookie = first(filter(header -> first(header) == "Set-Cookie",
                session_response.headers)) |> last
            cookie_identity = Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/hosted/me",
                ["Cookie" => first(split(session_cookie, ';'))]))
            @test cookie_identity.status == 200

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
            @test !isempty(claim_body["lease_token"])
            @test !isnothing(claim_body["lease_until"])
            local_remote_plan = select_suite_plan(
                plan_suite(software;
                    profile = :quick, version_provider = provider),
                remote_ids)
            remote_result = run_suite(local_remote_plan; executor = fake_runner,
                strict = false)
            remote_bundle = PerfChecker._suite_run_bundle(remote_result)
            completion = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/hosted/agents/complete",
                [auth_headers; "Content-Type" => "application/json"], JSON.json(Dict(
                    "agent_id" => "worker-1", "job_id" => claim_body["job_id"],
                    "lease_token" => claim_body["lease_token"],
                    "bundle" => bundle_dict(remote_bundle)))))
            @test completion.status == 200
            completion_body = JSON.parse(String(completion.body))
            @test completion_body["state"] == "complete"
            @test completion_body["progress"]["state"] == "complete"
            @test completion_body["progress"]["completed"] == length(remote_ids)
            @test completion_body["progress"]["remaining"] == 0
            @test completion_body["progress"]["percent"] == 100.0
            @test completion_body["progress"]["passed"] == length(remote_ids)
            @test isnothing(completion_body["progress"]["current_run"])
            cancel_launch = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/hosted/jobs",
                [auth_headers; "Content-Type" => "application/json"], JSON.json(Dict(
                    "profile" => "quick",
                    "plan_revision" => hosted_plan_body["plan_revision"],
                    "selected_run_ids" => remote_ids,
                    "execution_target" => "agent:worker-1"))))
            cancel_id = JSON.parse(String(cancel_launch.body))["job_id"]
            cancel_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/hosted/jobs/cancel",
                [auth_headers; "Content-Type" => "application/json"],
                JSON.json(Dict("job_id" => cancel_id))))
            @test cancel_response.status == 200
            @test JSON.parse(String(cancel_response.body))["state"] == "cancelled"
            Oxygen.resetstate()

            register_oxygen_routes!(bundle; prefix = "/test/perfchecker/bundle")
            bundle_response = Oxygen.internalrequest(
                HTTP.Request("GET", "/test/perfchecker/bundle/observations"))
            @test bundle_response.status == 200
            @test length(JSON.parse(String(bundle_response.body))) ==
                  length(bundle.observations)
            query_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/bundle/query", ["Content-Type" => "application/json"],
                JSON.json(performance_query_dict(PerformanceQuery(
                    resources = [:observations], predicates = [
                        QueryPredicate("metric", :equals, "julia.wall.time")])))))
            @test query_response.status == 200
            @test JSON.parse(String(query_response.body))["schema_version"] ==
                  "perfchecker-query-result/1"
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
            plot_response = Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/store/plots?id=$(bundle.manifest["run_id"])"))
            @test plot_response.status == 200
            plot_id = first(JSON.parse(String(plot_response.body))["plots"])["id"]
            plot_data_response = Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/store/plot-data?id=$(bundle.manifest["run_id"])&plot=$plot_id"))
            @test plot_data_response.status == 200
            @test JSON.parse(String(plot_data_response.body))["schema_version"] ==
                  "perfchecker-plot/1"
            makie_response = Oxygen.internalrequest(HTTP.Request("GET",
                "/test/perfchecker/store/plot?id=$(bundle.manifest["run_id"])&plot=$plot_id"))
            @test makie_response.status == 200
            @test occursin("canvas", lowercase(String(makie_response.body)))
            Oxygen.resetstate()

            ingest_store = joinpath(dir, "ingested-bundles")
            register_oxygen_routes!(ingest_store;
                prefix = "/test/perfchecker/ingest", allow_ingest = true,
                max_ingest_bytes = 4_096)
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
            unsafe_payload = copy(provider_payload)
            unsafe_payload["run_id"] = "../../outside"
            unsafe_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/ingest/ingest", ["Content-Type" => "application/json"],
                JSON.json(unsafe_payload)))
            @test unsafe_response.status == 400
            oversized_response = Oxygen.internalrequest(HTTP.Request("POST",
                "/test/perfchecker/ingest/ingest", ["Content-Type" => "application/json"],
                repeat("x", 4_097)))
            @test oversized_response.status == 413
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

            profile_bundle = PerfChecker.RunBundle(
                Dict(
                    "schema_version" => PerfChecker.RUN_BUNDLE_SCHEMA,
                    "run_id" => "profile-export", "suite" => "demo", "state" => "complete"),
                Dict{String, Any}[], [Dict{String, Any}(
                    "metric" => "julia.cpu.samples", "case_id" => "demo/case",
                    "version" => "dev", "value" => 3,
                    "attributes" => Dict("stack" => ["root (a.jl:1)", "leaf (b.jl:2)"]))],
                Dict{String, Any}[], Dict{String, Any}[])
            pprof_path = write_pprof_profile(profile_bundle,
                joinpath(dir, "profile.pb.gz"); max_samples = 20)
            @test isfile(pprof_path)
            @test filesize(pprof_path) > 0
            documenter_path = documenter_page(bundle,
                joinpath(dir, "docs", "performance.md"))
            @test occursin("# Performance", read(documenter_path, String))
            query = PerformanceQuery(; resources = [:observations, :plots],
                predicates = [QueryPredicate("metric", :equals, "julia.wall.time")],
                limit = 5)
            block = PerformanceDocumentBlock("runtime", "Runtime evidence", query;
                views = [:observations, :plots], interactive_url = "/runs/example")
            filtered_documenter_path = documenter_page(bundle,
                joinpath(dir, "docs", "filtered-performance.md"); blocks = [block])
            filtered_documenter = read(filtered_documenter_path, String)
            @test occursin("## Runtime evidence", filtered_documenter)
            @test occursin("Open the interactive PerfChecker view", filtered_documenter)
            @test hasmethod(documenter_vitepress_makedocs, Tuple{RunBundle})
            terminal = terminal_plot(compare_suite_versions(bundle))
            @test occursin("median", sprint(show, "text/plain", terminal))
            terminal_from_grammar = terminal_plot(bundle; kind = :version_series)
            @test occursin("median", sprint(show, "text/plain", terminal_from_grammar))
        end
    end
end
