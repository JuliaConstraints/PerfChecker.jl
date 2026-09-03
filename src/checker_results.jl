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
    if v.hwinfo === nothing
        println(io, '\t', "not recorded")
    else
        println(io, "CPU Information:")
        println(io, '\t', v.hwinfo.cpus)
        println(io, "Machine name: ", v.hwinfo.machine)
        println(io, "Word Size: ", v.hwinfo.word)
        println(io, "SIMD Bytes: ", v.hwinfo.simdbytes)
        println(
            io, "Core count (physical, total and threads per core): ", v.hwinfo.corecount)
    end

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
    result_tags = something(results.tags, Symbol[])
    matched = exact_match ? tags == result_tags : !isempty(result_tags ∩ tags)
    return matched ? [1] : Int[]
end

function find_by_tags(tags::Vector{Symbol}, results::AbstractVector{<:CheckerResult};
        exact_match = true)
    return findall(results) do result
        result_tags = something(result.tags, Symbol[])
        exact_match ? tags == result_tags : !isempty(result_tags ∩ tags)
    end
end

@testitem "Checker results" tags=[:unit, :results] begin
    using PerfChecker

    result = PerfChecker.CheckerResult(PerfChecker.Table[], nothing, [:a, :b],
        PerfChecker.PackageSpec[])
    @test find_by_tags([:a, :b], result) == [1]
    @test isempty(find_by_tags([:a], result))
    @test find_by_tags([:a], result; exact_match = false) == [1]
    @test find_by_tags([:a], [result, result]; exact_match = false) == [1, 2]
    @test occursin("not recorded", sprint(show, result))
end
