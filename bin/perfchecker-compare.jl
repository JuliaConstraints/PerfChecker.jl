using PerfChecker

function argument(name::String, default = nothing)
    prefix = "--$name="
    match = findfirst(value -> startswith(value, prefix), ARGS)
    return match === nothing ? default : ARGS[match][(length(prefix) + 1):end]
end

baseline_path = argument("baseline")
candidate_path = argument("candidate")
baseline_path === nothing && error("--baseline=<run-bundle> is required")
candidate_path === nothing && error("--candidate=<run-bundle> is required")
reports = abspath(argument("reports", joinpath("perf", "results", "comparison")))
minimum = parse(Int, argument("min-samples", "1"))

limits = Dict{String, Float64}()
for value in ARGS
    startswith(value, "--limit=") || continue
    metric, threshold = split(value[(length("--limit=") + 1):end], '='; limit = 2)
    limits[metric] = parse(Float64, threshold)
end

comparison = compare_bundles(read_run_bundle(baseline_path),
    read_run_bundle(candidate_path); relative_limits = limits, min_samples = minimum)
mkpath(reports)
write_comparison_json(comparison, joinpath(reports, "comparison.json"))
write_comparison_markdown(comparison, joinpath(reports, "comparison.md"))
println("PerfChecker comparison: $(comparison_passed(comparison) ? "PASS" : "FAIL")")
comparison_passed(comparison) || exit(1)
