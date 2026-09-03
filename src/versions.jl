"""
    get_pkg_versions(name::String, regname=nothing) -> Vector{VersionNumber}

Find all registered versions of `name` in the installed registries.

Example:

```julia-repl
julia> get_pkg_versions("ConstraintLearning")
7-element Vector{VersionNumber}:
 v"0.1.4"
 v"0.1.5"
 v"0.1.0"
 v"0.1.6"
 v"0.1.1"
 v"0.1.3"
 v"0.1.2"
```
The optional `regname` argument restricts the lookup to registry names.
"""
function get_pkg_versions(name::String,
        regname::Union{Nothing, Vector{String}} = nothing)::Vector{VersionNumber}
    regs = Context().registries
    indexes = isnothing(regname) ? collect(1:length(regs)) :
              findall(x -> x.name in regname, regs)

    versions::Set{String} = Set([])
    for i in indexes
        key = join([first(name), name, "Versions.toml"], '/')
        registry = regs[i].in_memory_registry
        if registry isa Dict && haskey(registry, key)
            push!(versions, keys(parse(registry[key]))...)
            continue
        end

        path = joinpath(regs[i].path, string(first(name)), name, "Versions.toml")
        isfile(path) || continue
        push!(versions, keys(parse(read(path, String)))...)
    end
    return sort!(VersionNumber.(collect(versions)))
end

const VerConfig = Tuple{String, Symbol, Vector{VersionNumber}, Bool}

"""
    arrange_patches(version, versions, prefer_latest)

Return all versions with the same major and minor version.
"""
function arrange_patches(a::VersionNumber, v::Vector{VersionNumber}, ::Bool)
    a = filter(x -> a.minor == x.minor && a.major == x.major, v)
    if isempty(a)
        @warn "No matching version found"
        return Vector{VersionNumber}()
    end
    return a
end

function arrange_minor(a::VersionNumber, v::Vector{VersionNumber}, maxo::Bool)
    p = filter(x -> a.major == x.major && a.minor == x.minor, v)
    if isempty(p)
        @warn "No matching version found"
        return Vector{VersionNumber}()
    end
    return maxo ? [maximum(p)] : [minimum(p)]
end

"""
    arrange_breaking(version, versions, prefer_latest)

Return the first or last compatible breaking-version group. For `0.x` packages,
minor versions are treated as breaking; otherwise major versions are used.
"""
function arrange_breaking(a::VersionNumber, v::Vector{VersionNumber}, maxo::Bool)
    if a.major == 0
        return arrange_minor(a, v, maxo)
    else
        return arrange_major(a, v, maxo)
    end
end

"""
    arrange_major(version, versions, prefer_latest)

Return the first or last version with the same major version.
"""
function arrange_major(a::VersionNumber, v::Vector{VersionNumber}, maxo::Bool)
    p = filter(x -> a.major == x.major, v)
    if isempty(p)
        @warn "No matching version found"
        return Vector{VersionNumber}()
    end
    return maxo ? [maximum(p)] : [minimum(p)]
end

function arrange_custom(a::VersionNumber, v::Vector{VersionNumber}, ::Bool)
    return if a in v
        [a]
    else
        @warn "Version $a not found"
        return Vector{VersionNumber}()
    end
end

function get_versions(pkgconf::VerConfig, regname::Union{Nothing, Vector{String}} = nothing)
    versions = get_pkg_versions(pkgconf[1], regname)

    s = pkgconf[2]
    f = if s == :patches
        arrange_patches
    elseif s == :breaking
        arrange_breaking
    elseif s == :major
        arrange_major
    elseif s == :minor
        arrange_minor
    elseif s == :custom
        arrange_custom
    else
        error("Unknown option provided $s")
    end
    return pkgconf[1],
    collect(Iterators.flatten(map(x -> f(x, versions, pkgconf[4]), pkgconf[3])))
end

function get_versions(pkgconf::PackageVersionSpec,
        regname::Union{Nothing, Vector{String}} = nothing)
    return get_versions(
        (pkgconf.name, pkgconf.selector, pkgconf.versions, pkgconf.prefer_latest), regname)
end

@testitem "Version selection" tags=[:unit, :versions] begin
    import PerfChecker

    _, versions = PerfChecker.get_versions(
        ("PatternFolds", :custom, [v"0.2.1", v"0.2.4"], true))
    @test versions == [v"0.2.1", v"0.2.4"]
    @test PerfChecker.arrange_patches(v"1.2.3",
        [v"1.2.1", v"1.2.3", v"1.3.0"], false) == [v"1.2.1", v"1.2.3"]
end
