using PerfChecker

function values(name::String)
    prefix = "--$name="
    return [argument[(length(prefix) + 1):end]
            for argument in ARGS if startswith(argument, prefix)]
end

function option(name::String, default::String)
    matches = values(name)
    length(matches) <= 1 || error("--$name may be supplied only once")
    return isempty(matches) ? default : only(matches)
end

suite = option("suite", "")
isempty(suite) && error("--suite=path is required")
reports = option("reports", joinpath("perf", "julia-runtimes"))
profile = Symbol(option("profile", "ci"))
factory = Symbol(option("factory", "build_suite"))
baseline_selector = option("baseline", "release")
candidate_selectors = values("candidate")
isempty(candidate_selectors) && (candidate_selectors = ["rc", "nightly"])
timeout_seconds = Base.parse(Float64, option("timeout", "3600"))
min_samples = Base.parse(Int, option("min-samples", "1"))

limits = Dict{String, Float64}()
for item in values("limit")
    parts = split(item, '='; limit = 2)
    length(parts) == 2 || error("--limit must use metric=fraction")
    limits[parts[1]] = Base.parse(Float64, parts[2])
end

specs = JuliaRuntimeSpec[
    JuliaRuntimeSpec(:baseline, baseline_selector; role = :baseline),
]
for (index, selector) in enumerate(candidate_selectors)
    push!(specs, JuliaRuntimeSpec(Symbol("candidate_", index), selector;
        role = :candidate))
end

campaign = run_julia_runtime_campaign(specs;
    suite, reports, profile, factory, timeout_seconds,
    relative_limits = limits, min_samples, strict = false)
payload = julia_runtime_campaign_dict(campaign)
println("PerfChecker Julia runtime campaign: ", payload["passed"] ? "PASS" : "FAIL")
println("Reports: ", abspath(reports))
payload["passed"] || exit(1)
