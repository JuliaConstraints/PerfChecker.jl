const PERFORMANCE_QUERY_SCHEMA = "perfchecker-query/1"
const PERFORMANCE_QUERY_RESULT_SCHEMA = "perfchecker-query-result/1"
const PERFORMANCE_DOCUMENT_BLOCK_SCHEMA = "perfchecker-document-block/1"
const AGENT_EVIDENCE_SCHEMA = "perfchecker-agent-evidence/1"

const _QUERY_OPERATORS = Set((:equals, :not_equals, :one_of, :contains, :prefix,
    :greater_or_equal, :less_or_equal, :exists))
const _QUERY_RESOURCE_ORDER = (:observations, :diagnostics, :artifacts, :plots,
    :comparison)
const _QUERY_RESOURCES = Set(_QUERY_RESOURCE_ORDER)

"A portable predicate over a result field, an attribute, or a manifest field."
struct QueryPredicate
    field::String
    operator::Symbol
    value::Any
end

function QueryPredicate(field::AbstractString, operator::Symbol, value = nothing)
    path = strip(String(field))
    isempty(path) && throw(ArgumentError("a query predicate requires a field"))
    operator in _QUERY_OPERATORS || throw(ArgumentError(
        "unsupported query operator $operator"))
    operator === :one_of &&
        !(value isa AbstractVector || value isa Tuple || value isa Set) &&
        throw(ArgumentError("one_of requires a collection value"))
    operator === :exists && !(value === nothing || value isa Bool) &&
        throw(ArgumentError(
            "exists accepts only a boolean or no value"))
    return QueryPredicate(path, operator, value)
end

"A presentation-neutral selection over a PerfChecker run bundle."
struct PerformanceQuery
    id::String
    resources::Vector{Symbol}
    predicates::Vector{QueryPredicate}
    order_by::Vector{Pair{String, Symbol}}
    limit::Int
end

function PerformanceQuery(; id::AbstractString = "query",
        resources = [:observations, :diagnostics, :artifacts, :plots, :comparison],
        predicates = QueryPredicate[], order_by = Pair{String, Symbol}[],
        limit::Integer = 0)
    normalized_resources = Symbol.(resources)
    unsupported = setdiff(Set(normalized_resources), _QUERY_RESOURCES)
    isempty(unsupported) || throw(ArgumentError(
        "unsupported query resources: $(join(sort!(string.(collect(unsupported))), ", "))"))
    normalized_order = Pair{String, Symbol}[]
    for item in order_by
        field = strip(String(first(item)))
        direction = Symbol(last(item))
        isempty(field) && throw(ArgumentError("an order field cannot be empty"))
        direction in (:asc, :desc) || throw(ArgumentError(
            "query sort direction must be asc or desc"))
        push!(normalized_order, field => direction)
    end
    limit >= 0 || throw(ArgumentError("query limit must be non-negative"))
    return PerformanceQuery(String(id), unique!(normalized_resources),
        QueryPredicate[predicates...], normalized_order, Int(limit))
end

"A documentation-system-neutral block backed by one bundle query."
struct PerformanceDocumentBlock
    id::String
    title::String
    query::PerformanceQuery
    views::Vector{Symbol}
    interactive_url::Union{Nothing, String}
end

function PerformanceDocumentBlock(id::AbstractString, title::AbstractString,
        query::PerformanceQuery; views = [:summary, :comparison, :plots],
        interactive_url = nothing)
    normalized_views = unique!(Symbol.(views))
    supported = Set((:summary, :comparison, :observations, :diagnostics, :plots,
        :artifacts))
    unsupported = setdiff(Set(normalized_views), supported)
    isempty(unsupported) || throw(ArgumentError(
        "unsupported documentation views: $(join(sort!(string.(collect(unsupported))), ", "))"))
    url = interactive_url === nothing ? nothing : String(interactive_url)
    return PerformanceDocumentBlock(String(id), String(title), query,
        normalized_views, url)
end

"Parse one documentation block from the shared JSON-compatible grammar."
function performance_document_block(payload::AbstractDict)
    value(key, default) = get(payload, key, get(payload, Symbol(key), default))
    schema = value("schema_version", PERFORMANCE_DOCUMENT_BLOCK_SCHEMA)
    schema == PERFORMANCE_DOCUMENT_BLOCK_SCHEMA || throw(ArgumentError(
        "unsupported document block schema $schema"))
    query_payload = value("query", nothing)
    query_payload isa AbstractDict || throw(ArgumentError(
        "a document block requires a query object"))
    return PerformanceDocumentBlock(String(value("id", "")),
        String(value("title", "")), performance_query(query_payload);
        views = Symbol.(value("views", String[])),
        interactive_url = value("interactive_url", nothing))
end

"Read and minimally validate a shared interface configuration."
function read_ui_configuration(path::AbstractString)
    payload = JSON.parsefile(abspath(String(path)); use_mmap = false)
    payload isa AbstractDict || throw(ArgumentError(
        "documentation configuration must be a JSON object"))
    get(payload, "schema_version", nothing) == "perfchecker-ui-config/1" ||
        throw(ArgumentError("unsupported UI configuration schema"))
    selection = get(payload, "selection", nothing)
    selection isa AbstractDict || throw(ArgumentError(
        "UI configuration requires a selection object"))
    run_ids = get(selection, "run_ids", nothing)
    run_ids isa AbstractVector && all(id -> id isa AbstractString, run_ids) ||
        throw(ArgumentError("UI configuration selection requires string run_ids"))
    allunique(run_ids) || throw(ArgumentError(
        "UI configuration run_ids must be unique"))
    return Dict{String, Any}(string(key) => value for (key, value) in pairs(payload))
end

"Read a shared UI/documentation configuration and return its document blocks."
function read_document_blocks(path::AbstractString)
    payload = read_ui_configuration(path)
    documentation = get(payload, "documentation", Dict{String, Any}())
    documentation isa AbstractDict || throw(ArgumentError(
        "documentation configuration must be an object"))
    return [performance_document_block(block)
            for block in get(documentation, "blocks", Any[])]
end

function performance_query_dict(predicate::QueryPredicate)
    return Dict{String, Any}("field" => predicate.field,
        "operator" => string(predicate.operator), "value" => predicate.value)
end

function performance_query_dict(query::PerformanceQuery)
    return Dict{String, Any}(
        "schema_version" => PERFORMANCE_QUERY_SCHEMA,
        "id" => query.id,
        "resources" => string.(query.resources),
        "where" => performance_query_dict.(query.predicates),
        "order_by" => [Dict("field" => first(item), "direction" => string(last(item)))
                       for item in query.order_by],
        "limit" => query.limit)
end

"Parse and validate the language-neutral dictionary form of a report query."
function performance_query(payload::AbstractDict)
    schema = get(
        payload, "schema_version", get(payload, :schema_version,
            PERFORMANCE_QUERY_SCHEMA))
    schema == PERFORMANCE_QUERY_SCHEMA || throw(ArgumentError(
        "unsupported performance query schema $schema"))
    value(key, default) = get(payload, key, get(payload, Symbol(key), default))
    predicates = QueryPredicate[]
    for item in value("where", Any[])
        item isa AbstractDict || throw(ArgumentError("query predicates must be objects"))
        field = get(item, "field", get(item, :field, ""))
        operator = Symbol(get(item, "operator", get(item, :operator, "equals")))
        predicate_value = get(item, "value", get(item, :value, nothing))
        push!(predicates, QueryPredicate(field, operator, predicate_value))
    end
    order = Pair{String, Symbol}[]
    for item in value("order_by", Any[])
        item isa AbstractDict || throw(ArgumentError("query ordering must be objects"))
        field = get(item, "field", get(item, :field, ""))
        direction = Symbol(get(item, "direction", get(item, :direction, "asc")))
        push!(order, String(field) => direction)
    end
    return PerformanceQuery(; id = String(value("id", "query")),
        resources = Symbol.(value("resources", string.(_QUERY_RESOURCE_ORDER))),
        predicates, order_by = order, limit = Int(value("limit", 0)))
end

function _query_path(value, path::AbstractString)
    current = value
    for part in split(String(path), '.')
        if current isa AbstractDict
            if haskey(current, part)
                current = current[part]
            elseif haskey(current, Symbol(part))
                current = current[Symbol(part)]
            else
                return nothing, false
            end
        elseif current isa NamedTuple && Symbol(part) in propertynames(current)
            current = getproperty(current, Symbol(part))
        else
            return nothing, false
        end
    end
    return current, true
end

function _query_value(record, manifest, field::String)
    if startswith(field, "manifest.")
        return _query_path(manifest, chop(field; head = length("manifest."), tail = 0))
    end
    direct, found = _query_path(record, field)
    found && return direct, true
    attributes = get(record, "attributes", get(record, :attributes, nothing))
    attributes isa AbstractDict || return nothing, false
    return _query_path(attributes, field)
end

function _query_match(record, manifest, predicate::QueryPredicate)
    actual, found = _query_value(record, manifest, predicate.field)
    predicate.operator === :exists && return predicate.value === false ? !found : found
    found || return false
    expected = predicate.value
    predicate.operator === :equals &&
        return actual == expected || string(actual) == string(expected)
    predicate.operator === :not_equals &&
        return !(actual == expected || string(actual) == string(expected))
    predicate.operator === :one_of && return any(
        item -> actual == item || string(actual) == string(item), expected)
    predicate.operator === :contains && return occursin(lowercase(string(expected)),
        lowercase(string(actual)))
    predicate.operator === :prefix && return startswith(lowercase(string(actual)),
        lowercase(string(expected)))
    predicate.operator === :greater_or_equal && return actual isa Number &&
           expected isa Number && actual >= expected
    predicate.operator === :less_or_equal && return actual isa Number &&
           expected isa Number && actual <= expected
    return false
end

function _query_records(records, manifest, query::PerformanceQuery)
    selected = [Dict{String, Any}(string(key) => value
                for (key, value) in pairs(record))
                for record in records
                if all(predicate -> _query_match(record, manifest, predicate),
        query.predicates)]
    for (field, direction) in Iterators.reverse(query.order_by)
        sort!(selected; alg = MergeSort, rev = direction === :desc,
            by = record -> begin
                value, found = _query_value(record, manifest, field)
                !found ? (1, 2, 0.0, "") :
                value isa Number ? (0, 0, Float64(value), "") :
                (0, 1, 0.0, lowercase(string(value)))
            end)
    end
    query.limit > 0 && resize!(selected, min(length(selected), query.limit))
    return selected
end

function _query_comparison_records(bundle::RunBundle, query::PerformanceQuery)
    comparison = version_comparison_dict(compare_suite_versions(bundle))
    records = get(comparison, "comparisons", get(comparison, "records", Any[]))
    records isa AbstractVector || return Dict{String, Any}[]
    return _query_records(records, bundle.manifest, query)
end

"Execute a report query without invoking a measurement worker or mutating the bundle."
function query_bundle(bundle::RunBundle, query::PerformanceQuery)
    observations = :observations in query.resources ?
                   _query_records(bundle.observations, bundle.manifest, query) :
                   Dict{String, Any}[]
    diagnostics = :diagnostics in query.resources ?
                  _query_records(bundle.diagnostics, bundle.manifest, query) :
                  Dict{String, Any}[]
    artifacts = :artifacts in query.resources ?
                _query_records(bundle.artifacts, bundle.manifest, query) :
                Dict{String, Any}[]
    plots = :plots in query.resources ?
            _query_records(plot_catalog(bundle), bundle.manifest, query) :
            Dict{String, Any}[]
    comparison = :comparison in query.resources ?
                 _query_comparison_records(bundle, query) : Dict{String, Any}[]
    return Dict{String, Any}(
        "schema_version" => PERFORMANCE_QUERY_RESULT_SCHEMA,
        "query" => performance_query_dict(query),
        "run" => Dict("run_id" => get(bundle.manifest, "run_id", nothing),
            "attempt_id" => get(bundle.manifest, "attempt_id", nothing),
            "suite" => get(bundle.manifest, "suite", nothing),
            "state" => get(bundle.manifest, "state", nothing),
            "runtime" => get(bundle.manifest, "runtime", Dict())),
        "counts" => Dict("observations" => length(observations),
            "diagnostics" => length(diagnostics), "artifacts" => length(artifacts),
            "plots" => length(plots), "comparison" => length(comparison)),
        "observations" => observations, "diagnostics" => diagnostics,
        "artifacts" => artifacts, "plots" => plots, "comparison" => comparison)
end

query_result_dict(bundle::RunBundle, query::PerformanceQuery) = query_bundle(bundle, query)

function performance_document_block(bundle::RunBundle,
        block::PerformanceDocumentBlock)
    return Dict{String, Any}(
        "schema_version" => PERFORMANCE_DOCUMENT_BLOCK_SCHEMA,
        "id" => block.id, "title" => block.title,
        "views" => string.(block.views),
        "interactive_url" => block.interactive_url,
        "provenance" => Dict(
            "run_id" => get(bundle.manifest, "run_id", nothing),
            "attempt_id" => get(bundle.manifest, "attempt_id", nothing),
            "evidence" => get(bundle.manifest, "evidence", nothing),
            "runtime" => get(bundle.manifest, "runtime", Dict()),
            "environment" => get(bundle.manifest, "environment", Dict()),
            "started_at" => get(bundle.manifest, "started_at", nothing),
            "finished_at" => get(bundle.manifest, "finished_at", nothing)),
        "result" => query_bundle(bundle, block.query))
end

"Create a bounded machine-readable evidence envelope for CI and AI workflows."
function agent_evidence(bundle::RunBundle, query::PerformanceQuery = PerformanceQuery();
        max_records::Integer = 100)
    max_records > 0 || throw(ArgumentError("max_records must be positive"))
    bounded = PerformanceQuery(; id = query.id, resources = query.resources,
        predicates = query.predicates, order_by = query.order_by,
        limit = query.limit == 0 ? Int(max_records) : min(query.limit, Int(max_records)))
    result = query_bundle(bundle, bounded)
    severities = Dict{String, Int}()
    for diagnostic in result["diagnostics"]
        severity = String(get(diagnostic, "severity", "unknown"))
        severities[severity] = get(severities, severity, 0) + 1
    end
    return Dict{String, Any}(
        "schema_version" => AGENT_EVIDENCE_SCHEMA,
        "generated_at" => string(Dates.now(Dates.UTC)),
        "run" => result["run"], "passed" => bundle_passed(bundle),
        "diagnostic_severities" => severities,
        "query_result" => result,
        "instructions" => Dict(
            "interpretation" => "compare only records with compatible measurement definitions and comparison keys",
            "evidence_policy" => "preserve unavailable, incomparable, and uncertain outcomes",
            "mutation_policy" => "this envelope does not authorize code changes, reruns, publication, or issue creation"))
end

@testitem "Portable performance query contract" tags=[:unit, :protocol, :query] begin
    using JSON
    using PerfChecker

    manifest = Dict{String, Any}("schema_version" => "perfchecker-run-bundle/1",
        "run_id" => "run-query", "attempt_id" => "attempt-query",
        "suite" => "demo", "state" => "complete",
        "runtime" => Dict("language" => "julia", "version" => "1.12.7"))
    observations = [Dict{String, Any}("record_type" => "observation",
                        "metric" => metric, "value" => value, "case_id" => "demo/pkg/feature",
                        "target_id" => version, "measurement_definition" => definition,
                        "attributes" => Dict("package" => "Pkg", "feature" => "parse",
                            "resource" => resource))
                    for (metric, value, version, definition, resource) in [
        ("julia.wall.time", 2.0, "1.0", "julia.wall.time/test-v1", "cpu"),
        ("julia.alloc.bytes", 32.0, "1.0", "julia.alloc.bytes/test-v1", "memory")]]
    bundle = RunBundle(manifest, Dict{String, Any}[], observations,
        Dict{String, Any}[], Dict{String, Any}[])
    query = PerformanceQuery(; id = "julia-time",
        resources = [:observations], predicates = [
            QueryPredicate("manifest.runtime.language", :equals, "julia"),
            QueryPredicate("metric", :equals, "julia.wall.time"),
            QueryPredicate("resource", :one_of, ["cpu", "scheduler"])],
        order_by = ["value" => :desc])
    result = query_bundle(bundle, query)
    @test result["schema_version"] == "perfchecker-query-result/1"
    @test result["counts"]["observations"] == 1
    @test only(result["observations"])["value"] == 2.0
    @test performance_query(performance_query_dict(query)).id == "julia-time"
    block = PerformanceDocumentBlock("parse-speed", "Parse speed", query;
        views = [:summary, :observations], interactive_url = "/runs/run-query")
    model = performance_document_block(bundle, block)
    @test model["schema_version"] == "perfchecker-document-block/1"
    @test model["provenance"]["run_id"] == "run-query"
    block_payload = Dict{String, Any}(
        "schema_version" => "perfchecker-document-block/1",
        "id" => "parse-speed", "title" => "Parse speed",
        "query" => performance_query_dict(query),
        "views" => ["summary", "observations"],
        "interactive_url" => "/runs/run-query")
    parsed_block = performance_document_block(block_payload)
    @test parsed_block.id == block.id
    mktempdir() do root
        config = Dict("schema_version" => "perfchecker-ui-config/1",
            "suite" => "demo", "profile" => "quick",
            "selection" => Dict("run_ids" => String[]),
            "documentation" => Dict("blocks" => [block_payload]))
        path = joinpath(root, "ui.json")
        open(path, "w") do io
            JSON.print(io, config)
        end
        @test only(read_document_blocks(path)).title == "Parse speed"
    end
    evidence = agent_evidence(bundle, query; max_records = 5)
    @test evidence["schema_version"] == "perfchecker-agent-evidence/1"
    @test evidence["passed"]
end
