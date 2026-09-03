using PerfChecker

distribution = get(ENV, "PERFCHECKER_TEST_WSL_DISTRIBUTION", "Ubuntu")
isolation = NetworkIsolationSpec(; provider = :wsl2_netns, distribution)
capabilities = network_isolation_capabilities(isolation; probe = true)
capabilities["supported"] || error(capabilities["reason"])

root = pkgdir(PerfChecker)
linux_root = PerfChecker._wsl_path(isolation, root)
wsl_prefix = String["wsl.exe", "-d", distribution]
julia_executable = strip(read(
    Cmd(vcat(wsl_prefix,
        ["--", "sh", "-lc",
            raw"PATH=\"$HOME/.juliaup/bin:$PATH\"; command -v julia"])),
    String))
isempty(julia_executable) && error("Julia is unavailable in WSL")

mktempdir(; prefix = "perfchecker-wsl-network-") do environment
    linux_environment = PerfChecker._wsl_path(isolation, environment)
    prepare_code = "using Pkg; Pkg.develop(path=$(repr(linux_root))); Pkg.instantiate()"
    prepare = Cmd(vcat(wsl_prefix,
        ["--", julia_executable, "--project=$linux_environment",
            "--startup-file=no", "--history-file=no", "-e", prepare_code]))
    run(prepare)

    command = ["julia", "--project=$environment", "--startup-file=no",
        "--history-file=no",
        joinpath(root, "bin", "perfchecker-suite.jl"),
        "--suite=" * joinpath(root, "test", "fixtures", "network_isolated_suite.jl"),
        "--reports=" * joinpath(environment, "reports"),
        "--profile=quick", "--factory=build_suite"]
    result = measure_isolated_network_command(command;
        spec = isolation, directory = root,
        environment = Dict("PERFCHECKER_FIXTURE_ENV" => linux_environment),
        timeout_seconds = 180, strict = false)
    print(result.stdout)
    report = joinpath(environment, "reports", "suite-result.json")
    result.exit_code == 0 || begin
        isfile(report) && println(read(report, String))
        error("isolated suite failed with code $(result.exit_code): $(result.stderr)")
    end
    println("capture-provider=", result.counter_provider)
    println("process-tree-packets-sent=", result.sample.packets_sent)
    println("process-tree-packets-received=", result.sample.packets_received)
end
