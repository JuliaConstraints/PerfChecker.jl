"""
    table_to_csv(table::Table, path::String)

Write a `TypedTables.Table` to `path`, creating the parent directory if needed.
"""
function table_to_csv(t::Table, path::String)
    mkpath(dirname(path))
    CSV.write(path, t)
end

"""
    csv_to_table(path::String) -> Table

Read a CSV file written by PerfChecker into a `TypedTables.Table`.
"""
csv_to_table(path::String) = CSV.read(path, Table)

"""
    check_to_metadata_csv(backend, pkg, version, tags; metadata="")

Compatibility wrapper for the legacy metadata format. New runs use structured
metadata with result UUIDs and config hashes.
"""
function check_to_metadata_csv(
        x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol}; metadata = "")
    check_to_metadata(x, pkg, version, tags; metadata)
end
