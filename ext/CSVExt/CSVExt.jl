module CSVExt

using CSV
import TypedTables: Table

table_to_csv(t::Table, path::String) = CSV.write(path, t)

csv_to_table(path::String) = CSV.read(path, Table)

end
