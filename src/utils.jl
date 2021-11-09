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

version2string(path) = string(Pkg.project().version)

function version2string(paths::Vector{String})
    function get_version(path)
        Pkg.activate(path)
        v = version2string(path)
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
