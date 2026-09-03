get_uuid() = ENV["PERFCHECKER_UUID"]

uuid_seed(seed) = replace(String(seed), '\\' => '/')
stable_uuid(seed) = uuid5(get_uuid() |> Base.UUID, uuid_seed(seed))
stable_uuid_string(seed) = string(stable_uuid(seed))

"Terminate a controller process and, where supported, its complete child tree."
function _terminate_process_tree(process)
    process_running(process) || return nothing
    if Sys.iswindows()
        result = run(ignorestatus(`taskkill /PID $(getpid(process)) /T /F`); wait = true)
        success(result) || kill(process)
    else
        kill(process)
    end
    return nothing
end

function flatten_parameters(
        x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol})
    return join(vcat([x, pkg, string("v", version)], tags), "_")
end

function file_uuid(
        x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol})
    return uuid5(get_uuid() |> Base.UUID, flatten_parameters(x, pkg, version, tags))
end

function filename(x::Symbol, pkg::AbstractString, version,
        tags::Vector{Symbol}; ext::AbstractString)
    return "$(file_uuid(x, pkg, version, tags)).$ext"
end

metadata_path(path::AbstractString) = joinpath(path, "metadata", "metadata.csv")
output_path(path::AbstractString, u::UUID) = joinpath(path, "output", string(u) * ".csv")

tags_to_string(tags::Vector{Symbol}) = join(string.(tags), "|")

function hardware_id(hwinfo::HwInfo)
    return stable_uuid_string(join(
        string.([hwinfo.machine, hwinfo.word, hwinfo.simdbytes, hwinfo.corecount]), "|"))
end

function result_uuid(config::CheckConfig, pkg::AbstractString, version, block1, block2,
        hwinfo::HwInfo)
    seed = join(
        string.([
            config.backend,
            pkg,
            version,
            tags_to_string(config.tags),
            config.config_hash,
            repr(block1),
            repr(block2),
            string(Base.VERSION),
            hardware_id(hwinfo)
        ]),
        "|")
    return stable_uuid(seed)
end

function run_metadata(config::CheckConfig, pkg::AbstractString, version, block1, block2,
        hwinfo::HwInfo)
    u = result_uuid(config, pkg, version, block1, block2, hwinfo)
    return RunMetadata(
        config.backend,
        String(pkg),
        string(version),
        config.tags,
        config.config_hash,
        u,
        string(Base.VERSION),
        config.threads,
        string(Dates.now(Dates.UTC)),
        hardware_id(hwinfo)
    )
end

function write_run_metadata(metadata::AbstractString, run::RunMetadata)
    mkpath(dirname(metadata))
    append = isfile(metadata) && filesize(metadata) > 0
    CSV.write(metadata,
        (backend = [string(run.backend)],
            package = [run.package],
            version = [run.version],
            tags = [tags_to_string(run.tags)],
            config_hash = [run.config_hash],
            result_uuid = [string(run.result_uuid)],
            julia_version = [run.julia_version],
            threads = [run.threads],
            date = [run.date],
            hardware_id = [run.hardware_id]);
        append,
        header = !append)
    return run
end

function metadata_has_result(metadata::AbstractString, result::UUID)
    isfile(metadata) || return false
    lines = collect(eachline(metadata))
    isempty(lines) && return false
    startswith(first(lines), "backend,") || return false
    header = split(first(lines), ',')
    idx = findfirst(==("result_uuid"), header)
    idx === nothing && return false
    return any(lines[2:end]) do line
        cols = split(line, ',')
        length(cols) >= idx && cols[idx] == string(result)
    end
end

function cached_output_path(
        config::CheckConfig, pkg::AbstractString, version, block1, block2,
        hwinfo::HwInfo)
    metadata = metadata_path(config.path)
    u = result_uuid(config, pkg, version, block1, block2, hwinfo)
    path = output_path(config.path, u)
    if metadata_has_result(metadata, u) && isfile(path)
        return path
    end

    legacy_u = file_uuid(config.backend, pkg, version, config.tags)
    legacy_path = output_path(config.path, legacy_u)
    fp = flatten_parameters(config.backend, pkg, version, config.tags)
    if in_metadata(metadata, fp, get_uuid() |> Base.UUID) && isfile(legacy_path)
        return legacy_path
    end
    return nothing
end

function check_to_metadata(
        x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol}; metadata = "")
    fp = flatten_parameters(x, pkg, version, tags)
    u = get_uuid() |> Base.UUID

    if !isempty(metadata)
        f = isfile(metadata)
        f || mkpath(dirname(metadata))
        if !f || !in_metadata(metadata, fp, u)
            open(metadata, "a") do f
                @info "Writing metadata" metadata
                write(f, string(fp, ",", u, "\n"))
            end
        end
    end

    return fp, u
end

function in_metadata(metadata, fp, u)
    isfile(metadata) || return false
    found = false
    open(metadata, "r") do io
        for l in eachline(io)
            if l == string(fp, ",", u)
                found = true
                break
            end
        end
    end
    return found
end

@testitem "Cache identity" tags=[:unit, :cache] begin
    using PerfChecker

    mktempdir() do dir
        cfg = PerfChecker.normalize_config(:benchmark,
            Dict(:path => dir, :tags => [:cache], :threads => 1, :samples => 1))
        block1 = :(using Random)
        block2 = :(sum(1:10))
        hardware = PerfChecker.HwInfo()
        run = PerfChecker.run_metadata(cfg, "Example", v"1.2.3", block1, block2, hardware)
        output = PerfChecker.output_path(cfg.path, run.result_uuid)
        PerfChecker.table_to_csv(
            PerfChecker.Table(times = [1.0], gctimes = [0.0],
                bytes_or_memory = [0], memory = [0], allocs = [0]), output)
        PerfChecker.write_run_metadata(PerfChecker.metadata_path(cfg.path), run)

        @test PerfChecker.metadata_has_result(PerfChecker.metadata_path(cfg.path),
            run.result_uuid)
        @test PerfChecker.cached_output_path(
            cfg, "Example", v"1.2.3", block1, block2, hardware) == output
        changed = PerfChecker.normalize_config(:benchmark,
            Dict(:path => dir, :tags => [:cache], :threads => 1, :samples => 2))
        @test isnothing(PerfChecker.cached_output_path(
            changed, "Example", v"1.2.3", block1, block2, hardware))
    end
end
