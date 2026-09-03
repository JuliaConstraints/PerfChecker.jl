using PerfChecker

function build_suite()
    environment = joinpath(@__DIR__, "runtime_runner")
    source = joinpath(@__DIR__, "runtime_package")
    feature = FeatureSpec(:runtime_contract;
        backend = :network,
        entrypoint = joinpath(@__DIR__, "runtime_feature.jl"),
        comparison_key = "runtime.contract/v1",
        options = Dict(:network_repetitions => 2, :repeat => false, :quiet => true))
    package = PackageSuite("RuntimeFixture";
        environment, source,
        versions = VersionNumber[], include_dev = true,
        features = [feature])
    return SoftwareSuite(:runtime_campaign_fixture, [package])
end
