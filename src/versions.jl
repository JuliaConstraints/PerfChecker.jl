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
		push!(versions, keys(TOML.parse(regs[i].in_memory_registry[join([first(name),name,"Versions.toml"], '/')]))...)
	end
	return VersionNumber.(versions)
end

const VerConfig = Tuple{Symbol, Vector{VersionNumber}, Bool}

"""
Outputs the last patch or first patch of a version. 
If the input is 1.2.3, then the output is 1.2.0 or 1.2.9 (assuming both exist, and both are the first and last patch of the version)
"""
function arrange_patches(a::VersionNumber, v::Vector{VersionNumber}, maxo::Bool)
	a = filter(x -> a.minor == x.minor && a.major == x.major, v)
	isempty(a) && error("No matching version found")
	return maxo ? maximum(a) : minimum(a)
end

"""
Outputs the last breaking or next breaking version. 
If the input is 1.2.3, then the output is 1.2.0 or 1.3.0 (assuming both exist)
"""
function arrange_breaking(a::VersionNumber, v::Vector{VersionNumber}, maxo::Bool)
	p = !maxo && filter(x -> a.major == x.major && a.minor == x.minor, v)
	q = maxo && filter(x -> a.major == x.major && a.minor < x.minor, v)
	(isempty(p) || isempty(q)) && error("No matching version found.")
	return maxo ? minimum(q) : minimum(p)
end

"""
Outputs the earlier or next major version.
"""
function arrange_major(a::VersionNumber, v::Vector{VersionNumber}, maxo::Bool)
	p = maxo && filter(x -> a.major < x.major, v)
	q = !maxo && filter(x -> a.major > x.major, v)
	(isempty(p) || isempty(q)) && error("No matching version found.")
	return maxo ? minimum(p) : maximum(q)
end

function get_versions(name::String, pkgconf::VerConfig, head::Bool = true, regname::Union{Nothing, Vector{String}} = nothing)
	versions = get_pkg_versions(name, regname)
	s = pkgconf[1]
	f = if s == :patches
		arrange_patches
	elseif s == :breaking
		arrange_breaking
	elseif s == :major
		arrange_major
	else
		error("Unknown option provided $(pkgconf[1])")
	end
	return map(x -> f(x, versions, pkgconf[3]), pkgconf[2])
end


