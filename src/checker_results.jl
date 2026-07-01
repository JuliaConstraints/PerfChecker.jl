"""
    CheckerResult

Result returned by `@check`.

Fields:

- `tables`: one `TypedTables.Table` per package version or target.
- `hwinfo`: hardware information collected by the orchestrating process.
- `tags`: tags attached to the run.
- `pkgs`: package specs corresponding to `tables`.
"""
struct CheckerResult
    tables::Vector{Table}
    hwinfo::Union{HwInfo, Nothing}
    tags::Union{Nothing, Vector{Symbol}}
    pkgs::Vector{PackageSpec}
end

const CheckResult = CheckerResult

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

"""
    find_by_tags(tags::Vector{Symbol}, results; exact_match=true)

Find results whose tags match `tags`.

With `exact_match=true`, tags must match exactly. With `exact_match=false`, any
overlap is accepted.
"""
function find_by_tags(tags::Vector{Symbol}, results::CheckerResult; exact_match = true)
    findall(x -> exact_match ? (tags == x.tags) : (!isempty(x.tags ∩ tags)), results)
end
