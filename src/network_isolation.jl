const NETWORK_ISOLATION_SPEC_SCHEMA = "perfchecker-network-isolation-spec/1"
const ISOLATED_NETWORK_RESULT_SCHEMA = "perfchecker-isolated-network-result/1"
const NETWORK_ISOLATION_ENV = "PERFCHECKER_NETWORK_ISOLATION"

"A process-tree network-isolation request for native Linux or Linux through WSL2."
struct NetworkIsolationSpec
    provider::Symbol
    distribution::Union{Nothing, String}
    interface::String
    external_connectivity::Bool
    dns_servers::Vector{String}
end

function _network_dns_servers(value, external::Bool)
    servers = value === nothing ? (external ? ["1.1.1.1"] : String[]) :
              String.(collect(value))
    external || isempty(servers) ||
        throw(ArgumentError(
            "DNS servers only apply when external connectivity is enabled"))
    for server in servers
        octets = split(server, '.'; keepempty = true)
        length(octets) == 4 || throw(ArgumentError(
            "only IPv4 DNS server addresses are supported: $server"))
        all(
            octet -> tryparse(Int, octet) isa Int &&
                     0 <= Base.parse(Int, octet) <= 255, octets) ||
            throw(ArgumentError("invalid IPv4 DNS server address: $server"))
    end
    return servers
end

function NetworkIsolationSpec(; provider::Symbol = :auto, distribution = nothing,
        interface = nothing, external_connectivity::Bool = false, dns_servers = nothing)
    resolved = provider === :auto ?
               (Sys.iswindows() ? :wsl2_netns : :linux_netns) : provider
    resolved in (:linux_netns, :wsl2_netns) || throw(ArgumentError(
        "network isolation provider must be linux_netns or wsl2_netns"))
    normalized_interface = interface === nothing ?
                           (external_connectivity ? "tap0" : "lo") :
                           strip(String(interface))
    isempty(normalized_interface) && throw(ArgumentError(
        "an isolated network interface is required"))
    external_connectivity && normalized_interface == "lo" &&
        throw(ArgumentError(
            "external connectivity requires a dedicated TAP interface such as tap0"))
    distro = distribution === nothing ? nothing : strip(String(distribution))
    distro === "" && (distro = nothing)
    dns = _network_dns_servers(dns_servers, external_connectivity)
    return NetworkIsolationSpec(resolved, distro, normalized_interface,
        external_connectivity, dns)
end

function network_isolation_spec_dict(spec::NetworkIsolationSpec)
    return Dict{String, Any}(
        "schema_version" => NETWORK_ISOLATION_SPEC_SCHEMA,
        "provider" => string(spec.provider),
        "distribution" => spec.distribution,
        "interface" => spec.interface,
        "external_connectivity" => spec.external_connectivity,
        "dns_servers" => spec.dns_servers,
        "attribution_scope" => "isolated_process_tree",
        "requires_prepared_environment" => true)
end

function _network_executable(name::AbstractString)
    path = Sys.which(String(name))
    return path === nothing ? nothing : String(path)
end

"Describe whether a process-tree network namespace can be launched on this host."
function network_isolation_capabilities(
        spec::NetworkIsolationSpec =
        NetworkIsolationSpec(); probe::Bool = false)
    reason = ""
    supported = false
    if spec.provider === :linux_netns
        supported = Sys.islinux() && _network_executable("unshare") !== nothing &&
                    _network_executable("ip") !== nothing &&
                    _network_executable("timeout") !== nothing &&
                    _network_executable("nft") !== nothing &&
                    (!spec.external_connectivity ||
                     _network_executable("slirp4netns") !== nothing)
        supported || (reason = Sys.islinux() ?
                  "unshare, ip, nft, timeout, and (for external traffic) slirp4netns are required" :
                  "native Linux is required")
        if supported && probe
            command = Cmd(["unshare", "--user", "--map-root-user", "--net",
                "sh", "-c",
                "ip link set lo up && nft add table inet perfchecker" *
                (spec.external_connectivity ?
                 " && command -v slirp4netns >/dev/null" : "")])
            supported = success(pipeline(ignorestatus(command); stdout = devnull,
                stderr = devnull))
            supported || (reason = "this Linux host cannot create an nft-enabled netns")
        end
    else
        supported = Sys.iswindows() && _network_executable("wsl.exe") !== nothing
        supported || (reason = "WSL2 is unavailable")
        if supported && probe
            command = String["wsl.exe"]
            spec.distribution === nothing || append!(command, ["-d", spec.distribution])
            append!(command,
                ["--", "unshare", "--user", "--map-root-user",
                    "--net", "sh", "-c",
                    "ip link set lo up && command -v timeout >/dev/null && command -v nft >/dev/null" *
                    (spec.external_connectivity ?
                     " && command -v slirp4netns >/dev/null" : "")])
            supported = success(pipeline(ignorestatus(Cmd(command)); stdout = devnull,
                stderr = devnull))
            supported ||
                (reason = "the selected WSL distribution cannot create a netns with ip, nft, and timeout")
        end
    end
    return Dict{String, Any}(
        "schema_version" => "perfchecker-network-isolation-capabilities/1",
        "supported" => supported,
        "provider" => string(spec.provider),
        "reason" => reason,
        "capture_layer" => "isolated_interface",
        "attribution" => "isolated_process_tree",
        "interface" => spec.interface,
        "external_connectivity" => spec.external_connectivity,
        "dns_servers" => spec.dns_servers,
        "requires_prepared_environment" => true,
        "counter_providers" => ["nftables", "sysfs"],
        "counters" => ["bytes_sent", "bytes_received", "packets_sent",
            "packets_received", "discarded_sent", "discarded_received"])
end

function _wsl_prefix(spec::NetworkIsolationSpec)
    command = String["wsl.exe"]
    spec.distribution === nothing || append!(command, ["-d", spec.distribution])
    return command
end

function _wsl_path(spec::NetworkIsolationSpec, path::AbstractString)
    absolute = abspath(String(path))
    matched = match(r"^([A-Za-z]):[\\/](.*)$", absolute)
    if matched !== nothing
        drive = lowercase(matched.captures[1])
        tail = replace(matched.captures[2], '\\' => '/')
        return "/mnt/$drive/$tail"
    end
    command = _wsl_prefix(spec)
    append!(command, ["--", "wslpath", "-a", "-u", replace(absolute, '\\' => '/')])
    return strip(read(Cmd(command), String))
end

function _translate_wsl_argument(spec::NetworkIsolationSpec, argument::String)
    occursin(r"^[A-Za-z][A-Za-z0-9+.-]*://", argument) && return argument
    for prefix in ("--project=", "--suite=", "--reports=")
        startswith(argument, prefix) || continue
        path = argument[(lastindex(prefix) + 1):end]
        return prefix * (startswith(path, '/') ? path : _wsl_path(spec, path))
    end
    return occursin(r"^[A-Za-z]:[\\/]", argument) ?
           _wsl_path(spec, argument) : argument
end

function _isolated_network_command(spec::NetworkIsolationSpec,
        command::AbstractVector{<:AbstractString}, result_path::AbstractString;
        directory::AbstractString = pwd(), timeout_seconds::Real = 300)
    isempty(command) && throw(ArgumentError("an isolated command cannot be empty"))
    timeout_seconds > 0 || throw(ArgumentError("timeout must be positive"))
    capabilities = network_isolation_capabilities(spec; probe = false)
    capabilities["supported"] || throw(ArgumentError(capabilities["reason"]))
    payload = String.(command)
    root = abspath(String(directory))
    isdir(root) || throw(ArgumentError("command directory does not exist: $root"))
    limit = string(Float64(timeout_seconds))
    wrapper = joinpath(dirname(@__DIR__), "bin", "perfchecker-network-netns.sh")
    launcher = joinpath(dirname(@__DIR__), "bin", "perfchecker-network-launch.sh")
    isfile(wrapper) || error("network namespace wrapper is missing: $wrapper")
    isfile(launcher) || error("network namespace launcher is missing: $launcher")
    external = spec.external_connectivity ? "1" : "0"
    dns = isempty(spec.dns_servers) ? "-" : join(spec.dns_servers, ',')
    if spec.provider === :linux_netns
        netns = ["sh", launcher, wrapper]
        append!(netns, [abspath(String(result_path)), spec.interface, limit, external, dns])
        append!(netns, payload)
        return Cmd(Cmd(netns); dir = root)
    end
    result = _wsl_path(spec, result_path)
    wsl_root = _wsl_path(spec, root)
    wsl_wrapper = _wsl_path(spec, wrapper)
    wsl_launcher = _wsl_path(spec, launcher)
    translated = [_translate_wsl_argument(spec, argument) for argument in payload]
    invocation = _wsl_prefix(spec)
    append!(invocation,
        ["--cd", wsl_root, "--", "sh", wsl_launcher,
            wsl_wrapper, result, spec.interface, limit, external, dns])
    append!(invocation, translated)
    return Cmd(invocation)
end

struct IsolatedNetworkCommandResult
    sample::NetworkInterfaceSample
    exit_code::Int
    stdout::String
    stderr::String
    provider::String
    counter_provider::String
    command::Vector{String}
end

function _nft_counter(path::AbstractString, chain::AbstractString)
    isfile(path) || return nothing
    document = JSON.parsefile(path; use_mmap = false)
    for item in get(document, "nftables", Any[])
        rule = get(item, "rule", nothing)
        rule isa AbstractDict || continue
        get(rule, "chain", "") == chain || continue
        for expression in get(rule, "expr", Any[])
            counter = get(expression, "counter", nothing)
            counter isa AbstractDict || continue
            return (bytes = UInt64(counter["bytes"]),
                packets = UInt64(counter["packets"]))
        end
    end
    return nothing
end

function _parse_isolated_network_capture(path::AbstractString)
    lines = readlines(path)
    length(lines) == 2 || throw(ErrorException("invalid isolated network capture"))
    first_fields = split(lines[1], '\t'; keepempty = true)
    second_fields = split(lines[2], '\t'; keepempty = true)
    length(first_fields) == 12 && length(second_fields) == 5 ||
        throw(ErrorException("invalid isolated network capture fields"))
    first_fields[1] == "perfchecker-network-capture/1" ||
        throw(ErrorException("unsupported isolated network capture schema"))
    numbers = Base.parse.(UInt64, first_fields[3:end])
    dropped = Base.parse.(UInt64, second_fields[1:4])
    nft_input = _nft_counter(path * ".nft", "input")
    nft_output = _nft_counter(path * ".nft", "output")
    use_nft = nft_input !== nothing && nft_output !== nothing
    before = NetworkInterfaceSnapshot(first_fields[2], numbers[1],
        use_nft ? UInt64(0) : numbers[3], use_nft ? UInt64(0) : numbers[5],
        use_nft ? UInt64(0) : numbers[7], use_nft ? UInt64(0) : numbers[9],
        dropped[1], dropped[3], use_nft ? "linux-netns-nftables" : "linux-netns-sysfs")
    after = NetworkInterfaceSnapshot(first_fields[2], numbers[2],
        use_nft ? nft_output.bytes : numbers[4],
        use_nft ? nft_input.bytes : numbers[6],
        use_nft ? nft_output.packets : numbers[8],
        use_nft ? nft_input.packets : numbers[10],
        dropped[2], dropped[4], use_nft ? "linux-netns-nftables" : "linux-netns-sysfs")
    sample = network_interface_delta(before, after;
        capture_layer = "isolated_interface",
        attribution_scope = "isolated_process_tree",
        latency_context = "process_lifecycle_informative")
    return sample, Base.parse(Int, second_fields[5]), after.provider
end

"Run one command tree in an isolated network namespace and capture its counters."
function measure_isolated_network_command(command::AbstractVector{<:AbstractString};
        spec::NetworkIsolationSpec = NetworkIsolationSpec(),
        directory::AbstractString = pwd(), environment::AbstractDict = Dict(),
        timeout_seconds::Real = 300, strict::Bool = false)
    result_path, stream = mktemp()
    close(stream)
    rm(result_path; force = true)
    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()
    launched = nothing
    try
        isolated = _isolated_network_command(spec, command, result_path;
            directory, timeout_seconds)
        variables = [String(key) => String(value) for (key, value) in pairs(environment)]
        if !isempty(variables)
            all(pair -> occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", first(pair)), variables) ||
                throw(ArgumentError("isolated environment keys must be portable names"))
            if spec.provider === :wsl2_netns
                inherited = filter(!isempty, split(get(ENV, "WSLENV", ""), ':'))
                append!(inherited, first.(variables))
                push!(variables, "WSLENV" => join(unique(inherited), ':'))
            end
            isolated = addenv(isolated, variables...)
        end
        launched = run(
            pipeline(ignorestatus(isolated), stdout = stdout_buffer,
                stderr = stderr_buffer);
            wait = false)
        outer_timeout = timedwait(() -> !process_running(launched),
            Float64(timeout_seconds) + 5; pollint = 0.05)
        if outer_timeout === :timed_out
            _terminate_process_tree(launched)
            wait(launched)
            throw(ErrorException("isolated network command exceeded its shutdown grace period"))
        end
        wait(launched)
        output = String(take!(stdout_buffer))
        error_output = String(take!(stderr_buffer))
        isfile(result_path) || throw(ErrorException(
            "isolated network provider did not write its capture: " *
            first(error_output, 4096)))
        sample, captured_status,
        counter_provider = _parse_isolated_network_capture(result_path)
        captured_status == launched.exitcode || throw(ErrorException(
            "isolated network provider exit status mismatch"))
        strict && captured_status != 0 &&
            throw(ErrorException(
                "isolated network command failed with code $captured_status: " *
                first(error_output * "\n" * output, 8192)))
        return IsolatedNetworkCommandResult(sample, captured_status, output,
            error_output, string(spec.provider), counter_provider, String.(command))
    finally
        close(stdout_buffer)
        close(stderr_buffer)
        isfile(result_path) && rm(result_path; force = true)
        isfile(result_path * ".nft") && rm(result_path * ".nft"; force = true)
    end
end

function isolated_network_result_dict(result::IsolatedNetworkCommandResult;
        include_output::Bool = false, max_output_chars::Integer = 16_384)
    max_output_chars >= 0 || throw(ArgumentError("max_output_chars must be non-negative"))
    return Dict{String, Any}(
        "schema_version" => ISOLATED_NETWORK_RESULT_SCHEMA,
        "provider" => result.provider,
        "counter_provider" => result.counter_provider,
        "command" => result.command,
        "exit_code" => result.exit_code,
        "stdout" => include_output ? first(result.stdout, max_output_chars) : "",
        "stderr" => include_output ? first(result.stderr, max_output_chars) : "",
        "measurement_phase" => "process_lifecycle",
        "sample" => Dict(string(name) => getproperty(result.sample, name)
        for name in propertynames(result.sample)))
end

"Measure an in-process workload only when launched by PerfChecker's netns wrapper."
function measure_network_isolated(workload::Function; interface::AbstractString = "lo",
        repetitions::Integer = 1)
    get(ENV, NETWORK_ISOLATION_ENV, "") == "linux-netns-v1" ||
        throw(ArgumentError("isolated network measurement requires PerfChecker's network namespace wrapper"))
    Sys.islinux() || throw(ArgumentError("isolated network measurement requires Linux"))
    repetitions > 0 || throw(ArgumentError("network repetitions must be positive"))
    samples = NetworkInterfaceSample[]
    for _ in 1:Int(repetitions)
        before = _network_namespace_snapshot(interface)
        started = time_ns()
        workload()
        elapsed = (time_ns() - started) / 1.0e9
        after = _network_namespace_snapshot(interface)
        push!(samples,
            network_interface_delta(before, after;
                workload_seconds = elapsed, capture_layer = "isolated_interface",
                attribution_scope = "isolated_worker_group",
                latency_context = "workload_wall_time_informative"))
    end
    return samples
end

function _network_namespace_counter(chain::AbstractString)
    output = read(
        Cmd(["nft", "list", "chain", "inet", "perfchecker",
            String(chain)]), String)
    matched = match(r"counter packets\s+(\d+)\s+bytes\s+(\d+)", output)
    matched === nothing && error("nftables counter is unavailable for $chain")
    return (packets = Base.parse(UInt64, matched.captures[1]),
        bytes = Base.parse(UInt64, matched.captures[2]))
end

function _network_namespace_snapshot(interface::AbstractString)
    input = _network_namespace_counter("input")
    output = _network_namespace_counter("output")
    return NetworkInterfaceSnapshot(String(interface), time_ns(), output.bytes,
        input.bytes, output.packets, input.packets, UInt64(0), UInt64(0),
        "linux-netns-nftables")
end

prep(d::Dict, block::Expr, ::Val{:network_isolated}) = quote
    $block
    nothing
end

function default_options(::Val{:network_isolated})
    return Dict(:threads => 1, :track => "none", :repeat => true,
        :network_repetitions => 3, :network_interface => "lo")
end

function check(d::Dict, block::Expr, ::Val{:network_isolated})
    repetitions = Int(get(d, :network_repetitions, 3))
    interface = String(get(d, :network_interface, "lo"))
    return quote
        get(ENV, "PERFCHECKER_NETWORK_ISOLATION", "") == "linux-netns-v1" ||
            error("isolated network backend requires PerfChecker's network namespace wrapper")
        function isolated_counter(chain)
            output = read(
                Cmd(["nft", "list", "chain", "inet", "perfchecker",
                    chain]), String)
            matched = match(r"counter packets\s+(\d+)\s+bytes\s+(\d+)", output)
            matched === nothing && error("nftables counter is unavailable for " * chain)
            return (packets = Base.parse(UInt64, matched.captures[1]),
                bytes = Base.parse(UInt64, matched.captures[2]))
        end
        rows = NamedTuple[]
        for _ in 1:($repetitions)
            before_input = isolated_counter("input")
            before_output = isolated_counter("output")
            started = time_ns()
            $block
            elapsed = (time_ns() - started) / 1.0e9
            after_input = isolated_counter("input")
            after_output = isolated_counter("output")
            push!(rows,
                (
                    bytes_sent = Float64(after_output.bytes - before_output.bytes),
                    bytes_received = Float64(after_input.bytes - before_input.bytes),
                    packets_sent = Float64(after_output.packets - before_output.packets),
                    packets_received = Float64(after_input.packets - before_input.packets),
                    discarded_sent = 0.0, discarded_received = 0.0,
                    seconds = elapsed, workload_seconds = elapsed,
                    capture_layer = "isolated_interface",
                    attribution_scope = "isolated_worker_group",
                    interface = $interface,
                    latency_context = "workload_wall_time_informative"))
        end
        rows
    end
end

function post(d::Dict, ::Val{:network_isolated})
    NetworkInterfaceSample[record for record in d[:check_result]]
end

@testitem "Network isolation contracts" tags=[:unit, :network] begin
    using JSON
    using PerfChecker

    provider = Sys.iswindows() ? :wsl2_netns : :linux_netns
    spec = NetworkIsolationSpec(; provider)
    payload = network_isolation_spec_dict(spec)
    @test payload["attribution_scope"] == "isolated_process_tree"
    @test payload["external_connectivity"] == false
    external = NetworkIsolationSpec(; provider, external_connectivity = true)
    @test external.interface == "tap0"
    @test network_isolation_spec_dict(external)["external_connectivity"]
    @test external.dns_servers == ["1.1.1.1"]
    if Sys.iswindows()
        @test PerfChecker._translate_wsl_argument(external,
            "https://example.com/resource") == "https://example.com/resource"
        @test PerfChecker._translate_wsl_argument(external,
            "/etc/resolv.conf") == "/etc/resolv.conf"
    end
    @test NetworkIsolationSpec(; provider, external_connectivity = true,
        dns_servers = ["9.9.9.9"]).dns_servers == ["9.9.9.9"]
    @test_throws ArgumentError NetworkIsolationSpec(; provider,
        external_connectivity = true, dns_servers = ["invalid"])
    @test_throws ArgumentError NetworkIsolationSpec(; provider,
        external_connectivity = true, interface = "lo")
    @test_throws ArgumentError measure_network_isolated(() -> nothing)
    @test JSON.parsefile(
        joinpath(pkgdir(PerfChecker), "schemas",
            "perfchecker-network-isolation-spec-v1.schema.json");
        use_mmap = false)["type"] == "object"
    @test JSON.parsefile(
        joinpath(pkgdir(PerfChecker), "schemas",
            "perfchecker-isolated-network-result-v1.schema.json");
        use_mmap = false)["type"] == "object"
    definition = PerfChecker._definition_dict(
        "network.packets.sent/isolated-interface-v1", "1", :network_isolated)
    @test definition["includes_children"]
    @test definition["attribution_scope"] == "isolated_worker_group"

    mktempdir() do root
        capture = joinpath(root, "capture.tsv")
        write(capture,
            "perfchecker-network-capture/1\tlo\t1000000000\t2000000000\t0\t0\t0\t0\t0\t0\t0\t0\n" *
            "0\t0\t0\t0\t0\n")
        write(
            capture * ".nft", """{
        "nftables": [
          {"rule": {"chain": "input", "expr": [{"counter": {"packets": 5, "bytes": 500}}]}},
          {"rule": {"chain": "output", "expr": [{"counter": {"packets": 4, "bytes": 400}}]}}
        ]
      }""")
        sample, status,
        counter_provider = PerfChecker._parse_isolated_network_capture(capture)
        @test sample.bytes_sent == 400
        @test sample.bytes_received == 500
        @test sample.packets_sent == 4
        @test sample.packets_received == 5
        @test sample.attribution_scope == "isolated_process_tree"
        @test status == 0
        @test counter_provider == "linux-netns-nftables"
    end
end

@testitem "WSL isolated loopback capture" tags=[:integration, :network, :system] begin
    using PerfChecker

    enabled = get(ENV, "PERFCHECKER_TEST_WSL_NETWORK", "0") == "1"
    if Sys.iswindows() && enabled
        spec = NetworkIsolationSpec(; provider = :wsl2_netns,
            distribution = get(ENV, "PERFCHECKER_TEST_WSL_DISTRIBUTION", "Ubuntu"))
        @test network_isolation_capabilities(spec; probe = true)["supported"]
        fixture = joinpath(pkgdir(PerfChecker), "test", "fixtures", "network_loopback.jl")
        result = measure_isolated_network_command(
            ["julia", "--startup-file=no", fixture]; spec,
            directory = pkgdir(PerfChecker), timeout_seconds = 30, strict = true)
        @test result.exit_code == 0
        @test result.counter_provider == "linux-netns-nftables"
        @test result.sample.bytes_sent >= 262_144
        @test result.sample.bytes_received >= 262_144
        @test result.sample.packets_sent > 0
        @test result.sample.packets_received > 0
        @test result.sample.attribution_scope == "isolated_process_tree"
    else
        @test true
    end
end
