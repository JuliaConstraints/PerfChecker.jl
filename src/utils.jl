function oid2string(path::String)
    id = LibGit2.head_oid(LibGit2.GitRepo(path))
    return prod(i -> string(i; base=16, pad=2), id.val)
end

function oid2string(paths::Vector{String})
    function get_oid(path)
        oid = ""
        try
            oid = "-" * oid2string(path)
        catch _
            @warn "The target $path is not a git repository. Commit id for this target will be ignored to name the output."
        end
        return oid
    end

    return prod(get_oid, paths)
end

version2string() = string(Pkg.project().version)

function version2string(paths::Vector{String})
    function get_version(path)
        Pkg.activate(path)
        v = version2string()
        return if isnothing(v)
            @warn "The target $path is not a project folder. Versioning for this target will be ignored to name the output."
            ""
        else
            "-" * v
        end
    end

    save_path = dirname(Pkg.project().path)
    output = prod(get_version, paths)
    Pkg.activate(save_path)

    return output
end

function smart_paths(paths)
    splitted_paths = map(splitpath ∘ normpath, paths)

    @info "debug" paths splitted_paths
    common = paths |> first |> dirname |> splitpath
    for path in splitted_paths
        to_pop = length(common)
        for name in Iterators.zip(common, path)
            name[1] == name[2] || break
            to_pop -= 1
        end
        foreach(_ -> pop!(common), 1:to_pop)
    end

    for path in splitted_paths
        foreach(_ -> popfirst!(path), 1:length(common))
    end

    return joinpath(common...), map(joinpath, splitted_paths)
end
