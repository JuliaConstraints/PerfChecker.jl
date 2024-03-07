module PerfChecker

# SECTION - Imports
using Pkg
using Profile
import TypedTables: Table
import Distributed: remotecall_fetch, addprocs, rmprocs
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo
import Sys
import CpuId

struct HwInfo
    cpus::Vector{CPUInfo}
    machine::String
    word::Int
    simdbytes::Int
    corecount::Tuple{Int, Int}
end

struct CheckerResult
    table::Table
    hwinfo::HwInfo
    tags::Vector{Symbol}
end

find_by_tags(tags::Vector{Symbol}, results::CheckerResult; exact_match = true) = findall(x -> exact_match ? (tags == x.tags) : (!isempty(x.tags ∩ tags)), results)

# SECTION - Exports
export @check
export to_table

# SECTION - Includes

include("check.jl")
include("alloc.jl")

end
