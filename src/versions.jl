"""
Finds all versions of a package in all the installed registries and returns it as a vector.

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
"""
function get_pkg_versions(name::String, regname::Union{Nothing,Vector{String}} = nothing)::Vector{VersionNumber}
	regs = Types.Context().registries
    indexes = isnothing(regname) ? collect(1:length(regs)) : findall(x -> x.name in regname, regs)

	versions::Set{String} = Set([])
	for i in indexes
		push!(versions, keys(parse(regs[i].in_memory_registry[join([first(name),name,"Versions.toml"], '/')]))...)
	end
	return VersionNumber.(versions)
end

const VerConfig = Tuple{String, Symbol, Vector{VersionNumber}, Bool}

"""
Outputs the last patch or first patch of a version.
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
Outputs the last breaking or next breaking version. 
"""
function arrange_breaking(a::VersionNumber, v::Vector{VersionNumber}, maxo::Bool)
    if a.major == 0
        return arrange_minor(a, v, maxo)
    else
        return arrange_major(a, v, maxo)
    end
end

"""
Outputs the earlier or next major version.
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
	return pkgconf[1], Iterators.flatten(map(x -> f(x, versions, pkgconf[4]), pkgconf[3]))
end
