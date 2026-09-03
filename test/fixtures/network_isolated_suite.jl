using PerfChecker

function build_suite()
    root = dirname(dirname(@__DIR__))
    environment = get(ENV, "PERFCHECKER_FIXTURE_ENV", root)
    feature = FeatureSpec(:loopback_transport;
        backend = :network_isolated,
        entrypoint = joinpath(@__DIR__, "network_feature.jl"),
        comparison_key = "network.loopback.transport/v1",
        options = Dict(:network_repetitions => 2, :repeat => true, :quiet => true))
    package = PackageSuite("PerfChecker";
        environment = environment,
        source = root,
        versions = VersionNumber[],
        include_dev = true,
        features = [feature])
    return SoftwareSuite(:network_isolated_fixture, [package];
        description = "Deterministic loopback traffic in an isolated worker group")
end
