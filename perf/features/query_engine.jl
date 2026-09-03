using PerfChecker

function perf_setup()
    observations = [Dict{String, Any}(
                        "record_type" => "observation",
                        "case_id" => "perfchecker/self/query",
                        "target_id" => "dev@1.0.0-rc1",
                        "measurement_definition" => "julia.wall.time/self-v1",
                        "metric" => isodd(index) ? "julia.wall.time" : "julia.alloc.bytes",
                        "unit" => isodd(index) ? "ns" : "By",
                        "value" => Float64(index),
                        "attributes" => Dict(
                            "package" => "PerfChecker",
                            "feature" => "query_engine",
                            "resource" => isodd(index) ? "cpu" : "memory"))
                    for index in 1:4_000]
    manifest = Dict{String, Any}(
        "schema_version" => "perfchecker-run-bundle/1",
        "run_id" => "00000000-0000-0000-0000-000000000103",
        "attempt_id" => "00000000-0000-0000-0000-000000000103",
        "suite" => "perfchecker-self",
        "state" => "complete",
        "runtime" => Dict("language" => "julia", "version" => string(VERSION)),
        "environment" => Dict("os" => string(Sys.KERNEL), "architecture" => Sys.ARCH))
    bundle = RunBundle(manifest, Dict{String, Any}[], observations,
        Dict{String, Any}[], Dict{String, Any}[])
    query = PerformanceQuery(; id = "self-cpu",
        resources = [:observations],
        predicates = [
            QueryPredicate("metric", :equals, "julia.wall.time"),
            QueryPredicate("resource", :equals, "cpu")],
        order_by = ["value" => :desc], limit = 250)
    return bundle, query
end

perf_workload(state) = query_bundle(state...)
