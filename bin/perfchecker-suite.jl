using PerfChecker

function _argument(name::String, default::String)
    prefix = "--$name="
    match = findfirst(argument -> startswith(argument, prefix), ARGS)
    return match === nothing ? default : ARGS[match][(length(prefix) + 1):end]
end

suite_path = abspath(_argument("suite", joinpath("perf", "suite.jl")))
profile = Symbol(_argument("profile", get(ENV, "PERFCHECKER_PROFILE", "ci")))
reports = abspath(_argument("reports", joinpath("perf", "results", string(profile))))
factory = Symbol(_argument("factory", get(ENV, "PERFCHECKER_FACTORY", "build_suite")))

result = run_suite_file(suite_path; profile, reports, factory, strict = false)
println("PerfChecker $(result.plan.suite.id): " *
        (suite_passed(result) ? "PASS" : "FAIL") *
        " ($(length(result.runs)) feature/version runs)")
suite_passed(result) || exit(1)
