module PerfChecker

# SECTION - Imports
using Pkg
using Pkg.Types
import TOML: parse
using Profile
import TypedTables: Table
import Malt: remote_eval_wait, Worker, remote_eval_fetch, stop, fetch
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo
import Base.Sys: CPUinfo, CPU_NAME, cpu_info, WORD_SIZE
import CpuId: simdbytes, cpucores, cputhreads, cputhreads_per_core
import UUIDs: uuid4, uuid5
import JSON

function csv_to_table(path)
	# @warn "CSV module not loaded. Please load it before using this function."
end

function table_to_csv(t::Table, path::String)
	# @warn "CSV module not loaded. Please load it before using this function."
end

# SECTION - Exports
export @check
export to_table
export find_by_tags
export get_versions
export table_to_pie
export checkres_to_pie
export checkres_to_scatterlines
export saveplot
export csv_to_table
export table_to_csv
export checkres_to_boxplots
export check_to_metadata_csv

# SECTION - Includes
include("init.jl")
include("hwinfo.jl")
include("checker_results.jl")
include("utils.jl")
include("versions.jl")
include("check.jl")
include("alloc.jl")

end
