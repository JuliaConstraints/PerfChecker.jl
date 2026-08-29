const RUN_BUNDLE_SCHEMA = "perfchecker-run-bundle/1"
const PROVIDER_RESULT_SCHEMA = "perfchecker-provider-result/1"

"A self-contained, language-neutral performance result bundle."
struct RunBundle
    manifest::Dict{String, Any}
    measurement_definitions::Vector{Dict{String, Any}}
    observations::Vector{Dict{String, Any}}
    diagnostics::Vector{Dict{String, Any}}
    artifacts::Vector{Dict{String, Any}}
end

"A command provider that emits `perfchecker-provider-result/1` JSON."
struct ExternalCommandSpec
    id::Symbol
    language::String
    command::Vector{String}
    directory::String
    environment::Dict{String, String}
    timeout_seconds::Float64
end

function ExternalCommandSpec(id::Symbol, language::AbstractString,
        command::AbstractVector{<:AbstractString}; directory::AbstractString = pwd(),
        environment::AbstractDict = Dict{String, String}(), timeout_seconds::Real = 300)
    isempty(command) && throw(ArgumentError("an external provider command cannot be empty"))
    root = abspath(String(directory))
    isdir(root) || throw(ArgumentError("provider directory does not exist: $root"))
    timeout_seconds > 0 || throw(ArgumentError("provider timeout must be positive"))
    variables = Dict{String, String}(String(key) => String(value)
    for (key, value) in pairs(environment))
    return ExternalCommandSpec(id, String(language), String.(command), root, variables,
        Float64(timeout_seconds))
end

function external_command_dict(spec::ExternalCommandSpec)
    return Dict{String, Any}(
        "id" => string(spec.id),
        "language" => spec.language,
        "command" => spec.command,
        "directory" => spec.directory,
        "environment_keys" => sort!(collect(keys(spec.environment))),
        "timeout_seconds" => spec.timeout_seconds)
end

function _canonical_json(io::IO, value)
    if value === nothing || value isa Bool || value isa AbstractString
        print(io, JSON.json(value))
    elseif value isa Symbol || value isa VersionNumber || value isa UUID
        print(io, JSON.json(string(value)))
    elseif value isa Integer
        if abs(big(value)) <= big(2)^53 - 1
            print(io, value)
        else
            print(io, JSON.json(string(value)))
        end
    elseif value isa AbstractFloat
        isfinite(value) || throw(ArgumentError("canonical JSON does not permit NaN or Inf"))
        print(io, JSON.json(value))
    elseif value isa Real
        _canonical_json(io, Float64(value))
    elseif value isa AbstractDict
        print(io, '{')
        entries = sort!(collect(pairs(value)); by = pair -> string(first(pair)))
        for (index, pair) in enumerate(entries)
            index == 1 || print(io, ',')
            print(io, JSON.json(string(first(pair))), ':')
            _canonical_json(io, last(pair))
        end
        print(io, '}')
    elseif value isa NamedTuple
        _canonical_json(io,
            Dict(string(key) => getproperty(value, key)
            for key in propertynames(value)))
    elseif value isa Tuple || value isa AbstractVector || value isa Set
        print(io, '[')
        for (index, item) in enumerate(value)
            index == 1 || print(io, ',')
            _canonical_json(io, item)
        end
        print(io, ']')
    else
        _canonical_json(io, string(value))
    end
    return io
end

function _canonical_json(value)
    io = IOBuffer()
    _canonical_json(io, value)
    return String(take!(io))
end

_content_digest(value) = bytes2hex(SHA.sha256(codeunits(_canonical_json(value))))

function _write_json(path::AbstractString, value; canonical::Bool = false)
    open(path, "w") do io
        canonical ? _canonical_json(io, value) : JSON.print(io, value, 2)
        println(io)
    end
    return String(path)
end

function _write_jsonl(path::AbstractString, records)
    open(path, "w") do io
        for record in records
            _canonical_json(io, record)
            println(io)
        end
    end
    return String(path)
end

function _read_jsonl(path::AbstractString)
    isfile(path) || return Dict{String, Any}[]
    records = Dict{String, Any}[]
    for line in eachline(path)
        isempty(strip(line)) || push!(records, JSON.parse(line))
    end
    return records
end

function _measurement_definition(backend::Symbol, column::Symbol)
    if backend === :benchmark
        column === :times && return ("julia.wall.time/benchmarktools-v1", "ns")
        column === :gctimes && return ("julia.gc.time/benchmarktools-v1", "ns")
        column in (:bytes_or_memory, :memory) &&
            return ("julia.alloc.bytes/benchmarktools-v1", "By")
        column === :allocs && return ("julia.alloc.count/benchmarktools-v1", "1")
    elseif backend === :chairmark
        column === :times && return ("julia.wall.time/chairmarks-v1", "s")
        column === :gctimes && return ("julia.gc.fraction/chairmarks-v1", "1")
        column in (:bytes_or_memory, :bytes) &&
            return ("julia.alloc.bytes/chairmarks-v1", "By")
        column === :allocs && return ("julia.alloc.count/chairmarks-v1", "1")
    elseif backend === :alloc
        column === :bytes && return ("julia.alloc.bytes/line-tracking-v1", "By")
        column === :percentage &&
            return ("julia.alloc.fraction/line-tracking-v1", "%")
    elseif backend === :profile_alloc
        column === :bytes && return ("julia.alloc.bytes/profile-allocs-v1", "By")
        column === :allocs && return ("julia.alloc.count/profile-allocs-v1", "1")
    elseif backend === :profile
        column === :samples && return ("julia.cpu.samples/profile-v1", "1")
    elseif backend === :wall_profile
        column === :samples && return ("julia.wall.samples/profile-walltime-v1", "1")
    elseif backend === :network
        column === :bytes_sent && return ("network.io.sent/network-explicit-v1", "By")
        column === :bytes_received &&
            return ("network.io.received/network-explicit-v1", "By")
        column === :operations && return ("network.operations/network-explicit-v1", "1")
        column === :seconds && return ("julia.wall.time/network-explicit-v1", "s")
        column === :throughput_bytes_per_second &&
            return ("network.throughput/network-explicit-v1", "By/s")
        column === :operations_per_second &&
            return ("network.operations.rate/network-explicit-v1", "1/s")
    end
    return nothing
end

function _metric_name(definition_id::AbstractString)
    return first(split(String(definition_id), '/'))
end

function _definition_dict(id::String, unit::String, backend::Symbol)
    return Dict{String, Any}(
        "id" => id,
        "metric" => _metric_name(id),
        "unit" => unit,
        "collector" => string(backend),
        "sample_semantics" => "one backend sample",
        "preference" =>
            occursin("throughput", id) || occursin(".rate/", id) ?
            "higher" : "lower",
        "warmup_policy" =>
            backend in (:alloc, :profile_alloc, :profile,
                :wall_profile, :network) ?
            "explicit feature setup" : "collector controlled",
        "includes_compilation" => false,
        "includes_children" => false,
        "version" => 1)
end

function _metric_columns(backend::Symbol, names)
    candidates = if backend === :benchmark
        (:times, :gctimes, :memory, :allocs)
    elseif backend === :chairmark
        (:times, :gctimes, :bytes, :allocs)
    elseif backend === :alloc
        (:bytes, :percentage)
    elseif backend === :profile_alloc
        (:bytes, :allocs)
    elseif backend === :profile
        (:samples,)
    elseif backend === :wall_profile
        (:samples,)
    elseif backend === :network
        (:bytes_sent, :bytes_received, :operations, :seconds,
            :throughput_bytes_per_second, :operations_per_second)
    else
        Tuple(names)
    end
    return [name
            for name in candidates
            if name in names && _measurement_definition(backend, name) !== nothing]
end

function _result_protocol_records(result::SoftwareSuiteResult, run_id::String,
        attempt_id::String)
    definitions = Dict{String, Dict{String, Any}}()
    observations = Dict{String, Any}[]
    diagnostics = Dict{String, Any}[]
    for run in result.runs
        planned = run.planned
        case_id = "$(planned.suite)/$(planned.package_suite.id)/$(planned.feature.id)"
        target_id = planned.target.label
        if run.status !== :pass
            rule = run.status === :unavailable ? "feature.unavailable" : "feature.failed"
            severity = run.status === :unavailable ? "info" : "error"
            push!(diagnostics,
                Dict{String, Any}(
                    "record_type" => "diagnostic",
                    "run_id" => run_id,
                    "attempt_id" => attempt_id,
                    "case_id" => case_id,
                    "target_id" => target_id,
                    "rule_id" => rule,
                    "severity" => severity,
                    "message" => run.message,
                    "fingerprint" => _content_digest((rule, case_id, run.message)),
                    "evidence" => Dict("status" => string(run.status))))
            continue
        end
        run.result isa CheckerResult || continue
        backend = planned.feature.backend
        for (table_index, table) in enumerate(run.result.tables)
            names = propertynames(table)
            columns = _metric_columns(backend, names)
            for column in columns
                definition_id, unit = _measurement_definition(backend, column)
                definitions[definition_id] = _definition_dict(definition_id, unit, backend)
                values = getproperty(table, column)
                for (sample_index, value) in enumerate(values)
                    value isa Number || continue
                    value isa AbstractFloat && !isfinite(value) && continue
                    attributes = Dict{String, Any}(
                        "package" => planned.package_suite.package,
                        "feature" => string(planned.feature.id),
                        "version" => planned.target.label,
                        "target_kind" => string(planned.target.kind),
                        "table_index" => table_index)
                    if backend in (:alloc, :profile_alloc, :profile, :wall_profile)
                        :filename in names &&
                            (attributes["source_file"] = getproperty(table, :filename)[sample_index])
                        :line in names &&
                            (attributes["source_line"] = getproperty(table, :line)[sample_index])
                        :stack in names &&
                            (attributes["stack"] = getproperty(table, :stack)[sample_index])
                        for field in (:runtime_dispatch, :gc_event, :inference_status,
                            :inferred_return_type)
                            field in names || continue
                            attributes[string(field)] = getproperty(table, field)[sample_index]
                        end
                    end
                    push!(observations,
                        Dict{String, Any}(
                            "record_type" => "observation",
                            "run_id" => run_id,
                            "attempt_id" => attempt_id,
                            "case_id" => case_id,
                            "target_id" => target_id,
                            "metric" => _metric_name(definition_id),
                            "value" => value,
                            "unit" => unit,
                            "aggregation" => "sample",
                            "sample_index" => sample_index,
                            "scope" => "workload",
                            "attributes" => attributes,
                            "measurement_definition" => definition_id,
                            "comparison_key" => "$(planned.comparison_key)::$definition_id"))
                end
            end
        end
    end
    return sort!(collect(values(definitions)); by = definition -> definition["id"]),
    observations, diagnostics
end

function _suite_run_bundle(result::SoftwareSuiteResult; run_id = uuid4(),
        attempt_id = uuid4(), evidence::AbstractString = "fresh")
    logical_id = string(run_id)
    physical_id = string(attempt_id)
    definitions, observations, diagnostics = _result_protocol_records(
        result, logical_id, physical_id)
    identity = Dict{String, Any}(
        "plan" => suite_plan_dict(result.plan),
        "runtime" => string(VERSION),
        "definitions" => definitions)
    manifest = Dict{String, Any}(
        "schema_version" => RUN_BUNDLE_SCHEMA,
        "run_id" => logical_id,
        "attempt_id" => physical_id,
        "reuse_key" => _content_digest(identity),
        "evidence" => String(evidence),
        "state" => suite_passed(result) ? "complete" : "failed",
        "suite" => string(result.plan.suite.id),
        "profile" => string(result.plan.profile),
        "plan" => suite_plan_dict(result.plan),
        "started_at" => result.started_at,
        "finished_at" => result.finished_at,
        "runtime" => Dict(
            "language" => "julia",
            "version" => string(VERSION),
            "executable" => joinpath(Sys.BINDIR, Base.julia_exename()),
            "threads" => Threads.nthreads()),
        "environment" => Dict(
            "os" => string(Sys.KERNEL),
            "architecture" => string(Sys.ARCH),
            "word_size" => Sys.WORD_SIZE),
        "collector_capabilities" => sort!(unique!(
            [string(run.planned.feature.backend) for run in result.runs])),
        "warnings" => ["source revision and dirty state were not captured by this adapter"])
    return RunBundle(manifest, definitions, observations, diagnostics,
        Dict{String, Any}[])
end

function bundle_passed(bundle::RunBundle)
    get(bundle.manifest, "state", "failed") == "complete" &&
        !any(get(diagnostic, "severity", "") == "error"
        for diagnostic in bundle.diagnostics)
end

function bundle_dict(bundle::RunBundle; include_records::Bool = true)
    payload = Dict{String, Any}(
        "schema_version" => RUN_BUNDLE_SCHEMA,
        "manifest" => bundle.manifest,
        "passed" => bundle_passed(bundle))
    if include_records
        payload["measurement_definitions"] = bundle.measurement_definitions
        payload["observations"] = bundle.observations
        payload["diagnostics"] = bundle.diagnostics
        payload["artifacts"] = bundle.artifacts
    end
    return payload
end

"Write a run bundle using a temporary sibling and an atomic directory rename."
function write_run_bundle(bundle::RunBundle, directory::AbstractString)
    destination = abspath(String(directory))
    ispath(destination) &&
        throw(ArgumentError("bundle destination already exists: $destination"))
    parent = dirname(destination)
    mkpath(parent)
    temporary = destination * ".tmp-" * string(uuid4())
    mkpath(temporary)
    try
        _write_json(joinpath(temporary, "manifest.json"), bundle.manifest;
            canonical = true)
        _write_json(joinpath(temporary, "measurement-definitions.json"),
            bundle.measurement_definitions; canonical = true)
        _write_jsonl(joinpath(temporary, "observations.jsonl"), bundle.observations)
        _write_jsonl(joinpath(temporary, "diagnostics.jsonl"), bundle.diagnostics)
        _write_json(joinpath(temporary, "artifacts.json"), bundle.artifacts;
            canonical = true)
        mkpath(joinpath(temporary, "artifacts"))
        mv(temporary, destination)
    finally
        isdir(temporary) && rm(temporary; recursive = true, force = true)
    end
    return destination
end

function write_suite_bundle(result::SoftwareSuiteResult, root::AbstractString;
        run_id = uuid4(), attempt_id = uuid4(), evidence::AbstractString = "fresh")
    bundle = _suite_run_bundle(result; run_id, attempt_id, evidence)
    directory = joinpath(abspath(String(root)), "run-$(bundle.manifest["run_id"])")
    return write_run_bundle(bundle, directory)
end

function read_run_bundle(directory::AbstractString)
    root = abspath(String(directory))
    isdir(root) || throw(ArgumentError("bundle directory does not exist: $root"))
    manifest = JSON.parsefile(joinpath(root, "manifest.json"); use_mmap = false)
    get(manifest, "schema_version", nothing) == RUN_BUNDLE_SCHEMA ||
        throw(ArgumentError("unsupported run bundle schema"))
    definitions = JSON.parsefile(joinpath(root, "measurement-definitions.json");
        use_mmap = false)
    artifacts = JSON.parsefile(joinpath(root, "artifacts.json"); use_mmap = false)
    definitions isa AbstractVector || throw(ArgumentError("invalid definitions document"))
    artifacts isa AbstractVector || throw(ArgumentError("invalid artifacts document"))
    return RunBundle(manifest, Dict{String, Any}.(definitions),
        _read_jsonl(joinpath(root, "observations.jsonl")),
        _read_jsonl(joinpath(root, "diagnostics.jsonl")),
        Dict{String, Any}.(artifacts))
end

function list_run_bundles(root::AbstractString; recursive::Bool = false)
    directory = abspath(String(root))
    isdir(directory) || return Dict{String, Any}[]
    manifests = Dict{String, Any}[]
    entries = if recursive
        sort!([walk_root
               for (walk_root, _, files) in walkdir(directory)
               if "manifest.json" in files])
    else
        sort!(readdir(directory; join = true))
    end
    for entry in entries
        isdir(entry) || continue
        manifest_path = joinpath(entry, "manifest.json")
        isfile(manifest_path) || continue
        try
            manifest = JSON.parsefile(manifest_path; use_mmap = false)
            get(manifest, "schema_version", nothing) == RUN_BUNDLE_SCHEMA || continue
            manifest["bundle_path"] = entry
            push!(manifests, manifest)
        catch error
            @debug "ignoring unreadable PerfChecker bundle" entry exception=(
                error, catch_backtrace())
        end
    end
    return manifests
end

function _validate_provider_definition(definition)
    definition isa AbstractDict ||
        throw(ArgumentError("provider definition must be an object"))
    for key in ("id", "metric", "unit")
        value = get(definition, key, nothing)
        value isa AbstractString && !isempty(value) ||
            throw(ArgumentError("provider definition requires $key"))
    end
    occursin('.', definition["metric"]) ||
        throw(ArgumentError("provider metrics must use a namespaced identifier"))
    return Dict{String, Any}(string(key) => value for (key, value) in pairs(definition))
end

function _validate_provider_observation(observation, definitions, run_id, attempt_id,
        case_id, target_id)
    observation isa AbstractDict ||
        throw(ArgumentError("provider observation must be an object"))
    metric = get(observation, "metric", nothing)
    metric isa AbstractString && occursin('.', metric) ||
        throw(ArgumentError("provider observation requires a namespaced metric"))
    value = get(observation, "value", nothing)
    value isa Number || throw(ArgumentError("provider observation value must be numeric"))
    value isa AbstractFloat && !isfinite(value) &&
        throw(ArgumentError("provider observation value must be finite"))
    definition = get(observation, "measurement_definition", nothing)
    haskey(definitions, definition) ||
        throw(ArgumentError("provider observation references an unknown definition"))
    unit = get(observation, "unit", nothing)
    unit isa AbstractString && !isempty(unit) ||
        throw(ArgumentError("provider observation requires an explicit unit"))
    metric == definitions[definition]["metric"] ||
        throw(ArgumentError("provider observation metric differs from its definition"))
    unit == definitions[definition]["unit"] ||
        throw(ArgumentError("provider observation unit differs from its definition"))
    attributes = get(observation, "attributes", Dict{String, Any}())
    attributes isa AbstractDict ||
        throw(ArgumentError("observation attributes must be an object"))
    if metric == "network.io.payload"
        get(attributes, "capture_layer", nothing) == "application" ||
            throw(ArgumentError("payload network metrics require capture_layer=application"))
        get(attributes, "direction", nothing) in ("in", "out", "bidirectional") ||
            throw(ArgumentError("payload network metrics require an explicit direction"))
    end
    normalized = Dict{String, Any}(string(key) => item
    for (key, item) in pairs(observation))
    normalized["record_type"] = "observation"
    normalized["run_id"] = run_id
    normalized["attempt_id"] = attempt_id
    normalized["case_id"] = string(get(normalized, "case_id", case_id))
    normalized["target_id"] = string(get(normalized, "target_id", target_id))
    normalized["aggregation"] = get(normalized, "aggregation", "sample")
    normalized["scope"] = get(normalized, "scope", "workload")
    normalized["attributes"] = Dict{String, Any}(
        string(key) => item for (key, item) in pairs(attributes))
    return normalized
end

function _provider_result(payload::AbstractDict)
    get(payload, "schema_version", nothing) == PROVIDER_RESULT_SCHEMA ||
        throw(ArgumentError("unsupported provider result schema"))
    definitions = [_validate_provider_definition(definition)
                   for definition in get(payload, "measurement_definitions", Any[])]
    definition_index = Dict(definition["id"] => definition for definition in definitions)
    length(definition_index) == length(definitions) ||
        throw(ArgumentError("provider definition identifiers must be unique"))
    run_id = string(get(payload, "run_id", uuid4()))
    attempt_id = string(get(payload, "attempt_id", uuid4()))
    case_id = string(get(payload, "case_id", "external"))
    target_id = string(get(payload, "target_id", case_id))
    observations = [_validate_provider_observation(observation, definition_index,
                        run_id, attempt_id, case_id, target_id)
                    for observation in get(payload, "observations", Any[])]
    diagnostics = Dict{String, Any}[Dict{String, Any}(string(key) => item
                                    for (key, item) in pairs(diagnostic))
                                    for diagnostic in get(payload, "diagnostics", Any[])]
    for diagnostic in diagnostics
        diagnostic["record_type"] = "diagnostic"
        diagnostic["run_id"] = run_id
        diagnostic["attempt_id"] = attempt_id
        diagnostic["case_id"] = get(diagnostic, "case_id", case_id)
        diagnostic["target_id"] = get(diagnostic, "target_id", target_id)
    end
    artifacts = Dict{String, Any}[Dict{String, Any}(string(key) => item
                                  for (key, item) in pairs(artifact))
                                  for artifact in get(payload, "artifacts", Any[])]
    manifest = Dict{String, Any}(
        "schema_version" => RUN_BUNDLE_SCHEMA,
        "run_id" => run_id,
        "attempt_id" => attempt_id,
        "reuse_key" => string(get(payload, "reuse_key", _content_digest(payload))),
        "evidence" => string(get(payload, "evidence", "fresh")),
        "state" => string(get(payload, "state", "complete")),
        "suite" => string(get(payload, "suite", "external")),
        "case_id" => case_id,
        "started_at" => string(get(payload, "started_at", "")),
        "finished_at" => string(get(payload, "finished_at", "")),
        "runtime" => get(payload, "runtime", Dict("language" => "unknown")),
        "environment" => get(payload, "environment", Dict{String, Any}()),
        "collector_capabilities" => get(payload, "collector_capabilities", String[]),
        "warnings" => get(payload, "warnings", String[]))
    return RunBundle(manifest, definitions, observations, diagnostics, artifacts)
end

"Read and validate a language-neutral provider result."
function read_provider_result(path::AbstractString)
    _provider_result(JSON.parsefile(abspath(String(path)); use_mmap = false))
end

function _failed_provider_bundle(spec::ExternalCommandSpec, message::String)
    run_id = string(uuid4())
    attempt_id = string(uuid4())
    diagnostic = Dict{String, Any}(
        "record_type" => "diagnostic",
        "run_id" => run_id,
        "attempt_id" => attempt_id,
        "case_id" => string(spec.id),
        "rule_id" => "provider.failed",
        "severity" => "error",
        "message" => message,
        "fingerprint" => _content_digest((spec.id, message)),
        "evidence" => Dict("language" => spec.language))
    manifest = Dict{String, Any}(
        "schema_version" => RUN_BUNDLE_SCHEMA,
        "run_id" => run_id,
        "attempt_id" => attempt_id,
        "reuse_key" => _content_digest(external_command_dict(spec)),
        "evidence" => "fresh",
        "state" => "failed",
        "suite" => "external",
        "case_id" => string(spec.id),
        "runtime" => Dict("language" => spec.language),
        "environment" => Dict(
            "os" => string(Sys.KERNEL), "architecture" => string(Sys.ARCH)),
        "collector_capabilities" => String[],
        "warnings" => String[])
    return RunBundle(manifest, Dict{String, Any}[], Dict{String, Any}[],
        [diagnostic], Dict{String, Any}[])
end

function _remove_temporary_tree(path::AbstractString)
    isdir(path) || return nothing
    last_error = nothing
    for attempt in 1:40
        try
            if Sys.iswindows() && VERSION >= v"1.12"
                for (root, directories, files) in walkdir(path; topdown = false)
                    for file in files
                        rm(joinpath(root, file); force = true,
                            allow_delayed_delete = true)
                    end
                    for directory in directories
                        rm(joinpath(root, directory); force = true,
                            allow_delayed_delete = true)
                    end
                end
                rm(path; force = true, allow_delayed_delete = true)
            else
                rm(path; recursive = true, force = true)
            end
            ispath(path) || return nothing
        catch error
            last_error = (error, catch_backtrace())
        end
        sleep(0.05)
    end
    @warn "could not remove temporary directory" path exception=last_error
    return nothing
end

function _remove_temporary_file(path::AbstractString)
    isfile(path) || return nothing
    last_error = nothing
    for attempt in 1:40
        try
            if Sys.iswindows() && VERSION >= v"1.12"
                rm(path; force = true, allow_delayed_delete = true)
            else
                rm(path; force = true)
            end
            ispath(path) || return nothing
        catch error
            last_error = (error, catch_backtrace())
        end
        sleep(0.05)
    end
    @warn "could not remove provider result file" path exception=last_error
    return nothing
end

"Run a non-Julia provider in its own process and ingest its result grammar."
function run_external_command(spec::ExternalCommandSpec; bundle_root = nothing,
        strict::Bool = false)
    output_path, output_stream = mktemp()
    close(output_stream)
    rm(output_path; force = true)
    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()
    bundle = nothing
    try
        command = Cmd(Cmd(spec.command); dir = spec.directory)
        command = addenv(command, spec.environment...,
            "PERFCHECKER_OUTPUT" => output_path,
            "PERFCHECKER_CASE_ID" => string(spec.id))
        process = run(
            pipeline(ignorestatus(command), stdout = stdout_buffer,
                stderr = stderr_buffer);
            wait = false)
        wait_status = timedwait(() -> !process_running(process), spec.timeout_seconds;
            pollint = 0.05)
        if wait_status === :timed_out
            kill(process)
            wait(process)
            close(process)
            finalize(process)
            bundle = _failed_provider_bundle(spec,
                "provider timed out after $(spec.timeout_seconds) seconds")
        else
            wait(process)
            exit_code = process.exitcode
            process_succeeded = success(process)
            close(process)
            finalize(process)
            stderr_text = String(take!(stderr_buffer))
            if !process_succeeded
                detail = isempty(strip(stderr_text)) ? "no stderr" :
                         first(stderr_text, 4096)
                bundle = _failed_provider_bundle(spec,
                    "provider exited with code $exit_code: $detail")
            elseif !isfile(output_path)
                bundle = _failed_provider_bundle(spec,
                    "provider did not write PERFCHECKER_OUTPUT")
            else
                bundle = read_provider_result(output_path)
                bundle.manifest["provider"] = external_command_dict(spec)
                if !isempty(strip(stderr_text))
                    push!(bundle.diagnostics,
                        Dict{String, Any}(
                            "record_type" => "diagnostic",
                            "run_id" => bundle.manifest["run_id"],
                            "attempt_id" => bundle.manifest["attempt_id"],
                            "case_id" => string(spec.id),
                            "rule_id" => "provider.stderr",
                            "severity" => "warning",
                            "message" => first(stderr_text, 4096),
                            "fingerprint" => _content_digest(stderr_text),
                            "evidence" => Dict{String, Any}()))
                end
            end
        end
        if bundle_root !== nothing
            destination = joinpath(abspath(String(bundle_root)),
                "run-$(bundle.manifest["run_id"])")
            write_run_bundle(bundle, destination)
        end
        strict && !bundle_passed(bundle) && error("external provider $(spec.id) failed")
        return bundle
    finally
        close(stdout_buffer)
        close(stderr_buffer)
        _remove_temporary_file(output_path)
    end
end

@testitem "Portable run bundle protocol" tags=[:unit, :protocol] begin
    using JSON
    using PerfChecker
    import Pkg

    mktempdir() do dir
        @test JSON.parsefile(
            joinpath(pkgdir(PerfChecker), "schemas",
                "perfchecker-run-bundle-v1.schema.json");
            use_mmap = false)["type"] == "object"
        @test JSON.parsefile(
            joinpath(pkgdir(PerfChecker), "schemas",
                "perfchecker-provider-result-v1.schema.json");
            use_mmap = false)["type"] == "object"
        entrypoint = joinpath(dir, "feature.jl")
        write(entrypoint, "perf_workload(state) = nothing\n")
        feature = FeatureSpec(:portable; entrypoint,
            options = Dict(:samples => 1, :seconds => 0.01))
        package = PackageSuite("Example"; environment = dir, source = dir,
            versions = VersionNumber[v"1.0.0"], include_dev = false,
            features = [feature])
        plan = plan_suite(SoftwareSuite(:portable, [package]); profile = :release,
            version_provider = _ -> [v"1.0.0"])
        function fake(_, _, _, _)
            PerfChecker.CheckerResult(
                [PerfChecker.Table(times = [10.0, 12.0], gctimes = [1.0, 0.0],
                    memory = [8, 8], allocs = [1, 1])], nothing, [:portable],
                [Pkg.Types.PackageSpec(name = "Example", version = v"1.0.0")])
        end
        result = run_suite(plan; executor = fake)
        bundle_path = write_suite_bundle(result, joinpath(dir, "bundles"))
        bundle = read_run_bundle(bundle_path)
        @test bundle_passed(bundle)
        @test bundle.manifest["schema_version"] == "perfchecker-run-bundle/1"
        @test length(bundle.observations) == 8
        @test Set(observation["unit"] for observation in bundle.observations) ==
              Set(["ns", "By", "1"])
        @test all(occursin("::", observation["comparison_key"])
        for observation in bundle.observations)
        @test isdir(joinpath(bundle_path, "artifacts"))

        provider_path = joinpath(dir, "provider.json")
        write(provider_path,
            JSON.json(Dict(
                "schema_version" => "perfchecker-provider-result/1",
                "suite" => "mixed",
                "case_id" => "http-client",
                "runtime" => Dict("language" => "python", "version" => "3"),
                "measurement_definitions" => [Dict(
                    "id" => "network.io.payload/application-v1",
                    "metric" => "network.io.payload", "unit" => "By")],
                "observations" => [Dict(
                    "metric" => "network.io.payload", "value" => 128,
                    "unit" => "By", "measurement_definition" => "network.io.payload/application-v1",
                    "attributes" => Dict("capture_layer" => "application",
                        "direction" => "out"))])))
        provider = read_provider_result(provider_path)
        @test bundle_passed(provider)
        @test provider.observations[1]["attributes"]["direction"] == "out"

        invalid_path = joinpath(dir, "invalid-provider.json")
        invalid = JSON.parsefile(provider_path; use_mmap = false)
        delete!(invalid["observations"][1]["attributes"], "direction")
        write(invalid_path, JSON.json(invalid))
        @test_throws ArgumentError read_provider_result(invalid_path)
        invalid_unit = JSON.parsefile(provider_path; use_mmap = false)
        invalid_unit["observations"][1]["unit"] = "kB"
        write(invalid_path, JSON.json(invalid_unit))
        @test_throws ArgumentError read_provider_result(invalid_path)

        script = joinpath(dir, "provider.jl")
        write(script, """
using JSON
write(ENV["PERFCHECKER_OUTPUT"], JSON.json(Dict(
    "schema_version" => "perfchecker-provider-result/1",
    "suite" => "external", "case_id" => ENV["PERFCHECKER_CASE_ID"],
    "runtime" => Dict("language" => "julia-provider"),
    "measurement_definitions" => [Dict("id" => "custom.work/v1",
        "metric" => "custom.work", "unit" => "1")],
    "observations" => [Dict("metric" => "custom.work", "value" => 42,
        "unit" => "1", "measurement_definition" => "custom.work/v1")]
)))
""")
        spec = ExternalCommandSpec(:external, "julia-provider",
            [joinpath(Sys.BINDIR, Base.julia_exename()), "--startup-file=no",
                "--project=$(Base.active_project())", script]; directory = dir)
        external = run_external_command(spec)
        @test bundle_passed(external)
        @test external.observations[1]["value"] == 42
        @test !haskey(external_command_dict(spec), "environment")
        PerfChecker._remove_temporary_tree(dir)
    end
end
