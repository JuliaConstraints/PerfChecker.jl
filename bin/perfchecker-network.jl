using PerfChecker
import JSON

separator = findfirst(==("--"), ARGS)
separator === nothing && error(
    "usage: perfchecker-network.jl [options] -- command [arguments...]"
)
cli_arguments = ARGS[1:(separator - 1)]

function option(name::String, default::String)
    prefix = "--$name="
    index = findfirst(argument -> startswith(argument, prefix), cli_arguments)
    return index === nothing ? default : cli_arguments[index][(length(prefix) + 1):end]
end

command = String.(ARGS[(separator + 1):end])
isempty(command) && error("a command is required after --")

provider_text = option("provider", "auto")
provider = Symbol(provider_text)
distribution_text = option("distribution", "")
distribution = isempty(distribution_text) ? nothing : distribution_text
directory = abspath(option("directory", pwd()))
timeout_seconds = Base.parse(Float64, option("timeout", "300"))
output = abspath(option("output", joinpath(directory, "perfchecker-network-result.json")))
include_output = lowercase(option("include-output", "false")) in ("true", "1", "yes")
external_connectivity = lowercase(option("external", "false")) in ("true", "1", "yes")
interface_text = option("interface", "")
interface = isempty(interface_text) ? nothing : interface_text
dns_text = option("dns", "")
dns_servers = isempty(dns_text) ? nothing : split(dns_text, ',')

spec = NetworkIsolationSpec(; provider, distribution, interface,
    external_connectivity, dns_servers)
capabilities = network_isolation_capabilities(spec; probe = true)
capabilities["supported"] || error(capabilities["reason"])

println("PerfChecker network: launching isolated process tree")
result = measure_isolated_network_command(command;
    spec, directory, timeout_seconds, strict = false)
payload = isolated_network_result_dict(result; include_output)
mkpath(dirname(output))
temporary = output * ".tmp"
open(temporary, "w") do io
    JSON.print(io, payload, 2)
    println(io)
end
mv(temporary, output; force = true)

println("PerfChecker network: $(result.sample.packets_sent) sent packets, " *
        "$(result.sample.packets_received) received packets")
println("PerfChecker network: wrote $output")
exit(result.exit_code)
