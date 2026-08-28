using PerfChecker

function argument(name::String, default::String)
    prefix = "--$name="
    match = findfirst(value -> startswith(value, prefix), ARGS)
    return match === nothing ? default : ARGS[match][(length(prefix) + 1):end]
end

separator = findfirst(==("--"), ARGS)
separator === nothing && error("provider command must follow --")
command = ARGS[(separator + 1):end]
isempty(command) && error("provider command cannot be empty")

id = Symbol(argument("id", "external"))
language = argument("language", "unknown")
directory = abspath(argument("directory", pwd()))
reports = abspath(argument("reports", joinpath("perf", "results", "external")))
timeout = parse(Float64, argument("timeout", "300"))

spec = ExternalCommandSpec(id, language, command; directory, timeout_seconds = timeout)
bundle = run_external_command(spec; bundle_root = reports)
println("PerfChecker provider $(spec.id): $(bundle_passed(bundle) ? "PASS" : "FAIL") " *
        "($(length(bundle.observations)) observations)")
bundle_passed(bundle) || exit(1)
