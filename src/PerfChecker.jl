module PerfChecker

# SECTION - Imports
using Pkg
using Profile

import TypedTables: Table, showtable
import Distributed: remotecall_fetch, addprocs, rmprocs
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo

# SECTION - Exports
export @check
export to_table

# SECTION - Includes

include("check.jl")
include("alloc.jl")

end
