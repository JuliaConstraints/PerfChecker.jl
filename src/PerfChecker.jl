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

function find_by_tags(tags::Vector{Symbol}, results::CheckerResult; exact_match = true)
    results = []
    if exact_match
        for j in results
            if tags == j.tags
                push!(results, tags)
            else
        end
    else
        for j in results
            for i in tags
                if i in j.tags
                    push!(results, tags)
                    break
                end
            end
        end
    end
        
    return results
end

# SECTION - Exports
export @check
export to_table

# SECTION - Includes

include("check.jl")
include("alloc.jl")

end
