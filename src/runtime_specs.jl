const JULIA_RUNTIME_SPEC_SCHEMA = "perfchecker-julia-runtime-spec/1"
const JULIA_RUNTIME_PROBE_SCHEMA = "perfchecker-julia-runtime-probe/1"

"One explicit Julia runtime axis, independent from package-version targets."
struct JuliaRuntimeSpec
    id::Symbol
    selector::String
    role::Symbol
    source::Symbol
    executable::String
    arguments::Vector{String}
end

function JuliaRuntimeSpec(id::Symbol, selector::AbstractString;
        role::Symbol = :candidate, source::Symbol = :juliaup,
        executable::AbstractString = "julia", arguments = String[])
    role in (:baseline, :candidate, :control) || throw(ArgumentError(
        "Julia runtime role must be baseline, candidate, or control"))
    source in (:juliaup, :executable) || throw(ArgumentError(
        "Julia runtime source must be juliaup or executable"))
    normalized = strip(String(selector))
    isempty(normalized) && throw(ArgumentError("a Julia runtime selector is required"))
    command = String(executable)
    source === :executable && !isfile(command) &&
        throw(ArgumentError(
            "Julia executable does not exist: $command"))
    return JuliaRuntimeSpec(id, normalized, role, source, command, String.(arguments))
end

function julia_runtime_spec_dict(spec::JuliaRuntimeSpec)
    return Dict{String, Any}(
        "schema_version" => JULIA_RUNTIME_SPEC_SCHEMA,
        "id" => string(spec.id), "selector" => spec.selector,
        "role" => string(spec.role), "source" => string(spec.source),
        "executable" => spec.executable, "arguments" => spec.arguments)
end

"Build a hermetic-by-default Julia command prefix for a runtime spec."
function julia_runtime_command(spec::JuliaRuntimeSpec; project = nothing,
        startup_file::Bool = false, history_file::Bool = false,
        extra_arguments = String[])
    command = String[spec.executable]
    spec.source === :juliaup && push!(command, "+$(spec.selector)")
    append!(command, spec.arguments)
    push!(command, "--startup-file=$(startup_file ? "yes" : "no")")
    push!(command, "--history-file=$(history_file ? "yes" : "no")")
    project === nothing || push!(command, "--project=$(abspath(String(project)))")
    append!(command, String.(extra_arguments))
    return command
end

"Create the usual stable/candidate/nightly runtime axis without installing channels."
function julia_runtime_matrix(; baseline::AbstractString = "release",
        candidates = ["rc", "nightly"])
    specs = JuliaRuntimeSpec[JuliaRuntimeSpec(:baseline, baseline; role = :baseline)]
    for (index, selector) in enumerate(candidates)
        id = Symbol("candidate_", index)
        push!(specs, JuliaRuntimeSpec(id, String(selector); role = :candidate))
    end
    return specs
end

"Build a child-controller command that runs one suite under the selected Julia runtime."
function julia_runtime_suite_command(spec::JuliaRuntimeSpec;
        suite::AbstractString, reports::AbstractString,
        profile::Symbol = :ci, factory::Symbol = :build_suite,
        perfchecker_project::AbstractString = dirname(@__DIR__),
        controller_project::AbstractString = dirname(abspath(String(suite))),
        backend_packages::AbstractVector{<:AbstractString} = String[])
    suite_path = abspath(String(suite))
    isfile(suite_path) || throw(ArgumentError("suite file does not exist: $suite_path"))
    project = abspath(String(perfchecker_project))
    controller = abspath(String(controller_project))
    isfile(joinpath(controller, "Project.toml")) || throw(ArgumentError(
        "runtime controller Project.toml does not exist: $controller"))
    cli = joinpath(project, "bin", "perfchecker-runtime-suite.jl")
    isfile(cli) || throw(ArgumentError("PerfChecker suite CLI does not exist: $cli"))
    arguments = [cli, "--perfchecker-project=$project", "--suite=$suite_path",
        "--reports=$(abspath(String(reports)))", "--profile=$(string(profile))",
        "--factory=$(string(factory))"]
    append!(arguments, ["--backend-package=$(String(package))"
                        for package in backend_packages])
    return julia_runtime_command(spec; project = controller,
        extra_arguments = arguments)
end

"Resolve a Julia selector to the exact runtime identity observed in a fresh process."
function probe_julia_runtime(spec::JuliaRuntimeSpec; project = nothing)
    script = "print(string(VERSION), '\\t', Base.GIT_VERSION_INFO.commit, '\\t', Sys.BINDIR, '\\t', Base.libllvm_version)"
    command = julia_runtime_command(spec; project,
        extra_arguments = ["--compile=min", "-e", script])
    output = readchomp(Cmd(command))
    fields = split(output, '\t'; keepempty = true)
    length(fields) == 4 || throw(ErrorException(
        "unexpected Julia runtime probe output for $(spec.selector)"))
    return Dict{String, Any}(
        "schema_version" => JULIA_RUNTIME_PROBE_SCHEMA,
        "spec" => julia_runtime_spec_dict(spec),
        "version" => fields[1], "commit" => fields[2],
        "bindir" => fields[3], "llvm_version" => fields[4],
        "command" => command,
        "resolved_at" => string(Dates.now(Dates.UTC)))
end

@testitem "Julia runtime axis" tags=[:unit, :runtime, :protocol] begin
    using PerfChecker

    specs = julia_runtime_matrix(; baseline = "release", candidates = ["rc", "nightly"])
    @test length(specs) == 3
    @test specs[1].role == :baseline
    @test specs[2].selector == "rc"
    command = julia_runtime_command(specs[2]; project = pwd())
    @test command[1:2] == ["julia", "+rc"]
    @test "--startup-file=no" in command
    @test "--history-file=no" in command
    @test startswith(command[5], "--project=")
    @test julia_runtime_spec_dict(specs[3])["selector"] == "nightly"
    suite_command = julia_runtime_suite_command(specs[1]; suite = pathof(PerfChecker),
        reports = joinpath(pwd(), "runtime-results"),
        controller_project = pkgdir(PerfChecker))
    @test any(argument -> startswith(argument, "--suite="), suite_command)
    @test any(argument -> argument == "--profile=ci", suite_command)
    @test any(argument -> startswith(argument, "--perfchecker-project="), suite_command)
end
