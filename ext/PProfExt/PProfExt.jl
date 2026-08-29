module PProfExt

using Base.StackTraces: StackFrame
using FlameGraphs
using PerfChecker
using PProf

function _frame(label::String, pointer::UInt)
    match_result = match(r"^(.*) \((.*):(\d+)\)$", label)
    if match_result === nothing
        return StackFrame(Symbol(label), :none, 0, nothing, false, false, pointer)
    end
    return StackFrame(Symbol(match_result.captures[1]),
        Symbol(match_result.captures[2]), parse(Int, match_result.captures[3]),
        nothing, false, false, pointer)
end

function PerfChecker.write_pprof_profile(bundle::PerfChecker.RunBundle,
        path::AbstractString; metric::AbstractString = "julia.cpu.samples",
        case_id::AbstractString = "", version = nothing,
        max_samples::Integer = 100_000)
    max_samples > 0 || throw(ArgumentError("max_samples must be positive"))
    records = PerfChecker._profile_stack_records(bundle; metric, case_id, version)
    total = sum(record["value"] for record in records)
    total > 0 || throw(ArgumentError("profile weights must be positive"))
    keys = Dict{String, UInt}()
    lookup = Dict{UInt, Vector{StackFrame}}()
    next_key = UInt(1)
    data = UInt[]
    for record in records
        repeats = max(1, round(Int, record["value"] / total * max_samples))
        ids = UInt[]
        for label in record["stack"]
            id = get!(keys, label) do
                current = next_key
                next_key += 1
                lookup[current] = [_frame(label, current)]
                current
            end
            push!(ids, id)
        end
        sample = [reverse(ids); UInt(0)]
        for _ in 1:repeats
            append!(data, sample)
        end
    end
    destination = abspath(String(path))
    mkpath(dirname(destination))
    return PProf.pprof(data, lookup; web = false, out = destination)
end

end
