function _column(table, names::Tuple)
    cols = propertynames(table)
    for name in names
        name in cols && return getproperty(table, name)
    end
    return nothing
end

function _min_number(values)
    values === nothing && return missing
    numbers = Float64[x for x in values if x isa Number]
    return isempty(numbers) ? missing : minimum(numbers)
end

function _max_number(values)
    values === nothing && return missing
    numbers = Float64[x for x in values if x isa Number]
    return isempty(numbers) ? missing : maximum(numbers)
end

function _row_count(table)
    try
        return length(table)
    catch
        return missing
    end
end

"""
    summary_table(result::CheckerResult) -> Table

Build a compact table for REPL display or Pluto notebooks.

The summary uses a common schema across benchmark-like and allocation-like
tables. Missing metrics are reported as `missing` rather than inferred.
"""
function summary_table(result::CheckerResult)
    package = String[]
    version = String[]
    rows = Union{Missing, Int}[]
    min_time = Union{Missing, Float64}[]
    max_time = Union{Missing, Float64}[]
    min_memory = Union{Missing, Float64}[]
    max_memory = Union{Missing, Float64}[]
    min_allocs = Union{Missing, Float64}[]
    max_allocs = Union{Missing, Float64}[]

    for (idx, table) in pairs(result.tables)
        spec = idx <= length(result.pkgs) ? result.pkgs[idx] : PackageSpec()
        push!(package, something(spec.name, "current"))
        push!(version, string(something(spec.version, "")))
        push!(rows, _row_count(table))

        times = _column(table, (:times,))
        memory = _column(table, (:bytes_or_memory, :memory, :bytes))
        allocs = _column(table, (:allocs,))

        push!(min_time, _min_number(times))
        push!(max_time, _max_number(times))
        push!(min_memory, _min_number(memory))
        push!(max_memory, _max_number(memory))
        push!(min_allocs, _min_number(allocs))
        push!(max_allocs, _max_number(allocs))
    end

    return Table(;
        package,
        version,
        rows,
        min_time,
        max_time,
        min_memory,
        max_memory,
        min_allocs,
        max_allocs)
end

@testitem "Summary tables" tags=[:unit, :reporting] begin
    using PerfChecker
    import Pkg

    result = PerfChecker.CheckerResult(
        [PerfChecker.Table(times = [3.0, 1.0], bytes_or_memory = [20, 10],
            allocs = [2, 1])], nothing, [:unit],
        [Pkg.Types.PackageSpec(name = "Example", version = v"1.2.3")])
    summary = summary_table(result)
    @test summary.package[1] == "Example"
    @test summary.version[1] == "1.2.3"
    @test summary.min_time[1] == 1.0
    @test summary.max_memory[1] == 20.0
end
