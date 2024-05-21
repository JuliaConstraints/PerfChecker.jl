module CSVExt

using CSV
import TypedTables: Table

table_to_csv(t::Table, path::String) = CSV.write(path, t)

csv_to_table(path::String) = CSV.read(path, Table)

function check_to_metadata_csv(
		x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol}; metadata = "")
	check_to_metadata(x, pkg, version, tags; metadata)
end

end
