get_uuid() = ENV["PERFCHECKER_UUID"]

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

function check_to_metadata(
        x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol}; metadata = "")
    fp = flatten_parameters(x, pkg, version, tags)
    u = get_uuid() |> Base.UUID

    if !isempty(metadata)
        f = isfile(metadata)
        f || mkpath(dirname(metadata))
        if !f || !in_metadata(metadata, fp, u)
            open(metadata, "a") do f
                @info "Writing metada" metadata
                write(f, string(fp, ",", u, "\n"))
            end
        end
    end

    return fp, u
end

function in_metadata(metadata, fp, u)
    isfile(metadata) && for l in eachline(metadata)
        if l == string(fp, ",", u)
            return true
        end
    end
    return false
end
