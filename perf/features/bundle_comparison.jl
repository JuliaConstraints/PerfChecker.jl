using PerfChecker

function _self_bundle(run_id, scale)
    definition = Dict{String, Any}(
        "id" => "julia.wall.time/self-v1",
        "metric" => "julia.wall.time",
        "unit" => "ns",
        "preference" => "lower")
    observations = [Dict{String, Any}(
                        "record_type" => "observation",
                        "case_id" => "perfchecker/self/compare",
                        "target_id" => "dev@1.0.0-rc1",
                        "comparison_key" => "perfchecker-self-compare/v1",
                        "measurement_definition" => definition["id"],
                        "metric" => definition["metric"],
                        "unit" => definition["unit"],
                        "sample_index" => index,
                        "value" => scale * (100.0 + mod(index, 17)),
                        "attributes" => Dict(
                            "package" => "PerfChecker",
                            "feature" => "bundle_comparison",
                            "version" => "dev@1.0.0-rc1",
                            "target_kind" => "dev")) for index in 1:512]
    manifest = Dict{String, Any}(
        "schema_version" => "perfchecker-run-bundle/1",
        "run_id" => run_id,
        "attempt_id" => run_id,
        "suite" => "perfchecker-self",
        "state" => "complete",
        "runtime" => Dict("language" => "julia", "version" => string(VERSION)),
        "environment" => Dict("os" => string(Sys.KERNEL), "architecture" => Sys.ARCH))
    return RunBundle(manifest, [definition], observations,
        Dict{String, Any}[], Dict{String, Any}[])
end

function perf_setup()
    baseline = _self_bundle("00000000-0000-0000-0000-000000000101", 1.0)
    candidate = _self_bundle("00000000-0000-0000-0000-000000000102", 1.01)
    return baseline, candidate
end

perf_workload(bundles) = compare_bundles(bundles...; min_samples = 128)
