get_uuid() = ENV["PERFCHECKER_UUID"]

function flatten_parameters(x::Symbol, d::Dict)
	pkgs = d[:pkgs]
	tags = d[:tags]
	return vcat([x, pkgs[1], pkgs[2]], pkgs[3], [pkgs[4]], tags)
end

function file_uuid(x::Symbol, d::Dict)
	return uuid5(get_uuid() |> Base.UUID, join(flatten_parameters(x, d), "_"))
end

function filename(x::Symbol, d::Dict, ext::AbstractString)
	return "$(file_uuid(x, d)).$ext"
end

function check_to_metadata(x::Symbol, d::Dict; metadata = "")
	fp = join(flatten_parameters(x, d), "_")
	u = get_uuid() |> Base.UUID

	if !isempty(metadata)
		!isfile(metadata) && mkpath(dirname(metadata))
		open(metadata, "a") do f
			write(f, string(join(flatten_parameters(x, d), "_"), ",", u, "\n"))
		end
	end

	return fp, u
end
