function _profile_stack_records(bundle::RunBundle; metric::AbstractString,
        case_id::AbstractString = "", version = nothing)
    records = Dict{String, Any}[]
    for observation in bundle.observations
        get(observation, "metric", "") == metric || continue
        isempty(case_id) || get(observation, "case_id", "") == case_id || continue
        version === nothing || get(observation, "version", "") == string(version) ||
            continue
        stack = get(get(observation, "attributes", Dict()), "stack", nothing)
        stack isa AbstractVector || continue
        isempty(stack) && continue
        push!(records,
            Dict("stack" => String.(stack),
                "value" => Float64(observation["value"])))
    end
    isempty(records) &&
        throw(ArgumentError("no stack observations match the requested profile"))
    return records
end

function write_folded_profile(bundle::RunBundle, path::AbstractString;
        metric::AbstractString = "julia.cpu.samples", case_id::AbstractString = "",
        version = nothing)
    destination = abspath(String(path))
    mkpath(dirname(destination))
    records = _profile_stack_records(bundle; metric, case_id, version)
    open(destination, "w") do io
        for record in records
            labels = replace.(record["stack"], ';' => ':')
            println(io, join(labels, ';'), ' ', record["value"])
        end
    end
    return destination
end

function write_speedscope_profile(bundle::RunBundle, path::AbstractString;
        metric::AbstractString = "julia.cpu.samples", case_id::AbstractString = "",
        version = nothing)
    destination = abspath(String(path))
    mkpath(dirname(destination))
    records = _profile_stack_records(bundle; metric, case_id, version)
    labels = sort!(unique!(vcat((record["stack"] for record in records)...)))
    frame_index = Dict(label => index - 1 for (index, label) in enumerate(labels))
    samples = [[frame_index[label] for label in record["stack"]] for record in records]
    weights = [record["value"] for record in records]
    payload = Dict(
        "\$schema" => "https://www.speedscope.app/file-format-schema.json",
        "shared" => Dict("frames" => [Dict("name" => label) for label in labels]),
        "profiles" => [Dict("type" => "sampled", "name" => metric,
            "unit" => occursin("alloc", metric) ? "bytes" : "none",
            "startValue" => 0, "endValue" => sum(weights),
            "samples" => samples, "weights" => weights)],
        "activeProfileIndex" => 0, "exporter" => "PerfChecker.jl")
    open(destination, "w") do io
        JSON.print(io, payload, 2)
    end
    return destination
end

function write_pprof_profile end

@testitem "Portable profile exports" tags=[:unit, :profile, :exports] begin
    using PerfChecker
    using JSON

    bundle = PerfChecker.RunBundle(
        Dict("schema_version" => PerfChecker.RUN_BUNDLE_SCHEMA,
            "run_id" => "profile", "suite" => "demo", "state" => "complete"),
        Dict{String, Any}[], [Dict{String, Any}(
            "metric" => "julia.cpu.samples", "case_id" => "demo/case",
            "version" => "dev", "value" => 3,
            "attributes" => Dict("stack" => ["root (a.jl:1)", "leaf (b.jl:2)"]))],
        Dict{String, Any}[], Dict{String, Any}[])
    mktempdir() do dir
        folded = write_folded_profile(bundle, joinpath(dir, "profile.folded"))
        speedscope = write_speedscope_profile(
            bundle, joinpath(dir, "profile.speedscope.json"))
        @test occursin("root (a.jl:1);leaf (b.jl:2) 3", read(folded, String))
        @test JSON.parsefile(speedscope; use_mmap = false)["profiles"][1]["weights"] == [3]
    end
end
