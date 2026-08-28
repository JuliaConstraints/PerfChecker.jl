const VERSION_SELECTORS = (:patches, :breaking, :major, :minor, :custom)

"""
    PerfConfig(backend::Symbol; path=pwd(), kwargs...)
    PerfConfig(backend::Symbol, options)

Julia-native public configuration object for `@check`.

`PerfConfig` keeps the existing dictionary-based API available while giving
REPL, scripts, and Pluto notebooks a clearer object to pass around. Keyword
arguments are stored with symbolic keys and validated by `normalize_config`
just before a check runs.

Example:

```julia
config = PerfConfig(:benchmark; path=pwd(), tags=[:local], samples=10)
result = @check config begin
    nothing
end begin
    sum(1:100)
end
```
"""
struct PerfConfig
    backend::Symbol
    options::Dict{Symbol, Any}

    function PerfConfig(backend::Symbol, options::Dict{Symbol, Any})
        return new(backend, copy(options))
    end
end

function PerfConfig(backend::Symbol; path = pwd(), kwargs...)
    options = Dict{Symbol, Any}(:path => path)
    for (key, value) in pairs(kwargs)
        options[Symbol(key)] = value
    end
    return PerfConfig(backend, options)
end

function PerfConfig(backend::Symbol, options::AbstractDict)
    normalized = Dict{Symbol, Any}()
    for (key, value) in pairs(options)
        key isa Symbol ||
            throw(ArgumentError("PerfConfig option keys must be Symbol values"))
        normalized[key] = value
    end
    return PerfConfig(backend, normalized)
end

"""
    to_dict(config::PerfConfig) -> Dict{Symbol, Any}

Return a copy of the public options stored in `config`.
"""
to_dict(config::PerfConfig) = copy(config.options)

Base.Dict(config::PerfConfig) = to_dict(config)

"""
    PackageVersionSpec(name, selector, versions, prefer_latest)
    PackageVersionSpec(pkgconf::Tuple)

Normalized representation of the `:pkgs` option accepted by `@check`.

The tuple form is `(name::String, selector::Symbol,
versions::Vector{VersionNumber}, prefer_latest::Bool)`. Supported selectors
are `:custom`, `:patches`, `:minor`, `:major`, and `:breaking`.
"""
struct PackageVersionSpec
    name::String
    selector::Symbol
    versions::Vector{VersionNumber}
    prefer_latest::Bool
end

"""
    RunTarget(spec, label, is_dev)

Internal description of one package target to run in an isolated worker.
Released versions use `is_dev == false`; local development targets created from
`:devops` use `is_dev == true`.
"""
struct RunTarget
    spec::PackageSpec
    label::String
    is_dev::Bool
end

"""
    RunMetadata

Structured metadata written next to cached performance outputs. It records the
backend, package version, tags, normalized config hash, result UUID, Julia
version, thread count, timestamp, and hardware identity used for cache lookup.
"""
struct RunMetadata
    backend::Symbol
    package::String
    version::String
    tags::Vector{Symbol}
    config_hash::String
    result_uuid::UUID
    julia_version::String
    threads::Int
    date::String
    hardware_id::String
end

"""
    CheckConfig

Validated internal configuration used by PerfChecker after merging backend
defaults with the public `Dict` passed to `@check`.

Users can keep passing dictionaries; `CheckConfig` exists to make required
fields and cache identity explicit before workers are launched.
"""
struct CheckConfig
    backend::Symbol
    options::Dict{Symbol, Any}
    path::String
    tags::Vector{Symbol}
    threads::Int
    track::String
    packages::Union{Nothing, PackageVersionSpec}
    devops::Any
    extra_pkgs::Any
    targets::Vector{String}
    repeat::Bool
    include_current::Bool
    config_hash::String
end

function PackageVersionSpec(pkgconf::Tuple)
    length(pkgconf) == 4 ||
        throw(ArgumentError(":pkgs must be (name, selector, versions, prefer_latest)"))

    name, selector, versions, prefer_latest = pkgconf
    name isa AbstractString ||
        throw(ArgumentError(":pkgs first value must be a package name string"))
    selector isa Symbol ||
        throw(ArgumentError(":pkgs selector must be a Symbol"))
    selector in VERSION_SELECTORS ||
        throw(ArgumentError("unknown :pkgs selector $selector"))
    versions isa AbstractVector{VersionNumber} ||
        throw(ArgumentError(":pkgs versions must be a Vector{VersionNumber}"))
    prefer_latest isa Bool ||
        throw(ArgumentError(":pkgs prefer_latest must be Bool"))

    return PackageVersionSpec(String(name), selector, collect(versions), prefer_latest)
end

function normalize_symbols(value, key::Symbol; default = Symbol[])
    if value === nothing
        return collect(default)
    elseif value isa Symbol
        return [value]
    elseif value isa AbstractVector && all(x -> x isa Symbol, value)
        return Symbol.(value)
    else
        throw(ArgumentError("$key must be a Symbol or Vector{Symbol}"))
    end
end

function normalize_strings(value, key::Symbol; default = String[])
    if value === nothing
        return collect(default)
    elseif value isa AbstractString
        return [String(value)]
    elseif value isa AbstractVector && all(x -> x isa AbstractString, value)
        return String.(value)
    else
        throw(ArgumentError("$key must be a string or vector of strings"))
    end
end

"""
    normalize_config(backend::Symbol, config::Dict) -> CheckConfig

Merge backend defaults with a user configuration dictionary, validate shared
PerfChecker options, and return a `CheckConfig`.

Required shared option:

- `:path`: environment directory copied for each worker.

Common optional options include `:tags`, `:threads`, `:track`, `:pkgs`,
`:devops`, `:extra_pkgs`, `:targets`, and `:repeat`.
"""
function normalize_config(backend::Symbol, config::Dict)
    options = default_options(config, backend)

    haskey(options, :path) ||
        throw(ArgumentError("missing required :path option for @check $backend"))
    path = abspath(String(options[:path]))
    isdir(path) ||
        throw(ArgumentError(":path must point to an existing environment directory: $path"))

    tags = normalize_symbols(get(options, :tags, Symbol[:none]), :tags)
    threads = get(options, :threads, 1)
    threads isa Integer && threads > 0 ||
        throw(ArgumentError(":threads must be a positive integer"))
    track = String(get(options, :track, "none"))

    packages = haskey(options, :pkgs) ? PackageVersionSpec(options[:pkgs]) : nothing
    devops = get(options, :devops, nothing)
    extra_pkgs = get(options, :extra_pkgs, nothing)
    targets = normalize_strings(get(options, :targets, String[]), :targets)
    repeat = Bool(get(options, :repeat, true))
    include_current = Bool(get(options, :include_current, true))
    !include_current && packages === nothing && devops === nothing &&
        throw(ArgumentError(":include_current=false requires :pkgs or :devops"))
    option_pairs = sort!(collect(pairs(options)); by = p -> string(first(p)))
    option_fingerprint = join(map(p -> string(first(p), "=", repr(last(p))), option_pairs), "|")
    config_hash = stable_uuid_string(
        join(string.([backend, path, tags, threads, track, option_fingerprint]), "|"))

    return CheckConfig(
        backend, options, path, tags, Int(threads), track, packages, devops,
        extra_pkgs, targets, repeat, include_current, config_hash)
end

normalize_config(config::PerfConfig) = normalize_config(config.backend, to_dict(config))

function normalize_config(backend::Symbol, config::PerfConfig)
    backend == config.backend ||
        throw(ArgumentError(
            "backend mismatch: macro requested $backend but PerfConfig uses $(config.backend)"))
    return normalize_config(config)
end

function legacy_options(config::CheckConfig)
    options = copy(config.options)
    options[:path] = config.path
    options[:tags] = config.tags
    options[:threads] = config.threads
    options[:track] = config.track
    options[:targets] = config.targets
    options[:repeat] = config.repeat
    options[:include_current] = config.include_current
    config.packages === nothing ||
        (options[:pkgs] = (
            config.packages.name,
            config.packages.selector,
            config.packages.versions,
            config.packages.prefer_latest))
    config.devops === nothing || (options[:devops] = config.devops)
    config.extra_pkgs === nothing || (options[:extra_pkgs] = config.extra_pkgs)
    options[:config_hash] = config.config_hash
    return options
end

@testitem "Configuration contracts" tags=[:unit, :config] begin
    using PerfChecker

    cfg = PerfChecker.normalize_config(:benchmark,
        Dict(:path => @__DIR__, :tags => [:unit], :threads => 1))
    @test cfg.backend == :benchmark
    @test cfg.tags == [:unit]
    @test cfg.threads == 1
    @test cfg.path == abspath(@__DIR__)
    @test_throws ArgumentError PerfChecker.normalize_config(:benchmark, Dict())

    public_cfg = PerfConfig(:benchmark; path = @__DIR__, tags = [:ux], samples = 1)
    @test Dict(public_cfg)[:samples] == 1
    @test PerfChecker.normalize_config(public_cfg).backend == :benchmark
    @test_throws ArgumentError PerfChecker.normalize_config(:alloc, public_cfg)
    @test_throws ArgumentError PerfConfig(:benchmark, Dict("path" => @__DIR__))
    @test_throws ArgumentError PerfChecker.normalize_config(:benchmark,
        Dict(:path => @__DIR__, :include_current => false))
end
