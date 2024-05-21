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
		if !isfile(metadata)
			mkpath(dirname(metadata))
			open(metadata, "a") do f
				write(f, string(flatten_parameters(x, pkg, version, tags), ",", u, "\n"))
			end
		end
	end

	return fp, u
end

function check_to_metadata_csv(
		x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol}; metadata = "")
	@info "should not be here"
	return nothing
end
