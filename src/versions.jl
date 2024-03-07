const VerConfig = Tuple{Symbol, Vector{VersionNumber}, Bool}

struct PackVer
	pack::String
	ver::VerConfig
end

to_version_numbers(x) = to_version_numbers(x...)
to_version_numbers(s::Symbol, x...) = to_version_numbers(Val(s), x...)

function findmaxversion(d::String,m::String)
    l=m[1:1]
    a_path=joinpath(d,"registries","General",l,m)
    if isdir(d)&&isdir(a_path)
        di=Pkg.Operations.load_versions(a_path)
        return maximum(keys(di))
    end
    return v"0.0.0"
end

findmaxversion(m::String)=maximum(findmaxversion.(DEPOT_PATH,m))

function to_version_numbers(ver::VerConfig) end
