"""
    write_property_corpus(path, cases; producer="manual", metadata=Dict(), force=false)

Persist JSON-compatible property-generated cases before benchmarking them. The
result is an immutable input artifact: generation and shrinking do not run in
the timed worker.
"""
function write_property_corpus(path::AbstractString, cases::AbstractVector;
        producer::AbstractString = "manual", metadata::AbstractDict = Dict(),
        force::Bool = false)
    target = abspath(String(path))
    isfile(target) && !force &&
        throw(ArgumentError(
            "$target already exists; pass force=true to replace the frozen corpus"))
    payload = Dict{String, Any}(
        "schema_version" => "perfchecker-property-corpus/1",
        "producer" => String(producer),
        "created_at" => string(Dates.now(Dates.UTC)),
        "count" => length(cases),
        "metadata" => Dict(string(key) => value for (key, value) in pairs(metadata)),
        "cases" => collect(cases))
    mkpath(dirname(target))
    open(target, "w") do io
        JSON.print(io, payload, 2)
    end
    return target
end

function read_property_corpus(path::AbstractString)
    source = abspath(String(path))
    isfile(source) || throw(ArgumentError("property corpus does not exist: $source"))
    payload = JSON.parsefile(source; use_mmap = false)
    get(payload, "schema_version", nothing) == "perfchecker-property-corpus/1" ||
        throw(ArgumentError("unsupported property corpus schema in $source"))
    get(payload, "count", -1) == length(get(payload, "cases", Any[])) ||
        throw(ArgumentError("property corpus count does not match its cases in $source"))
    return payload
end

function freeze_supposition_corpus end
