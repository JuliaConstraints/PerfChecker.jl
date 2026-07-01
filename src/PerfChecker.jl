module PerfChecker

# SECTION - Imports
import Base.Sys: CPUinfo, CPU_NAME, cpu_info, WORD_SIZE
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo
import CpuId: simdbytes, cpucores, cputhreads, cputhreads_per_core
import CSV
import Dates
import JSON
import Malt: remote_eval_wait, Worker, remote_eval_fetch, stop, fetch
import Pkg
import Pkg.Types: PackageSpec, Context
import Profile
import TOML: parse
import TypedTables: Table
import UUIDs: UUID, uuid4, uuid5

# SECTION - Exports
export @check
export check_to_metadata_csv
export checkres_to_boxplots
export checkres_to_pie
export checkres_to_scatterlines
export csv_to_table
export find_by_tags
export get_versions
export PerfConfig
export perf_setup
export saveplot
export summary_table
export table_to_csv
export table_to_pie
export to_table
export write_template

# SECTION - Includes
include("init.jl")
include("hwinfo.jl")
include("config.jl")
include("checker_results.jl")
include("summary.jl")
include("utils.jl")
include("csv.jl")
include("versions.jl")
include("templates.jl")
include("check.jl")
include("alloc.jl")

end
