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

struct HwInfo
    cpus::Vector{CPUinfo}
    machine::String
    word::Int
    simdbytes::Int
    corecount::Tuple{Int, Int, Int}
end

struct CheckerResult
    tables::Vector{Table}
    hwinfo::Union{HwInfo, Nothing}
    tags::Union{Nothing, Vector{Symbol}}
    pkgs::Vector{PackageSpec}
end

function Base.show(io::IO, v::PerfChecker.CheckerResult)
    println(io, "Tables:")
    for i in v.tables
        println(io, '\t', Base.display(i))
    end

    println(io, "Hardware Info:")
    println(io, "CPU Information:")
    println(io, '\t', v.hwinfo.cpus)
    println(io, "Machine name: ", v.hwinfo.machine)
    println(io, "Word Size: ", v.hwinfo.word)
    println(io, "SIMD Bytes: ", v.hwinfo.simdbytes)
    println(io, "Core count (physical, total and threads per core): ", v.hwinfo.corecount)

    println(io, "Tags used: ", v.tags)

    println(io, "Package versions tested (if provided): ")
    println(io, Base.display(v.pkgs))
end

function find_by_tags(tags::Vector{Symbol}, results::CheckerResult; exact_match = true)
    findall(x -> exact_match ? (tags == x.tags) : (!isempty(x.tags ∩ tags)), results)
end

function csv_to_table(path)
    @warn "CSV module not loaded. Please load it before using this function."
end

function table_to_csv(t::Table, path::String)
    @warn "CSV module not loaded. Please load it before using this function."
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

# SECTION - Includes
include("versions.jl")
include("check.jl")
include("alloc.jl")

end
