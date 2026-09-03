using PerfChecker

function build_suite()
    root = normpath(joinpath(@__DIR__, ".."))
    common = Dict(:samples => 30, :evals => 1, :seconds => 0.4)
    plan_feature = FeatureSpec(:plan_generation;
        description = "Build a deterministic feature/version execution plan",
        entrypoint = joinpath(@__DIR__, "features", "plan_generation.jl"),
        comparison_key = "perfchecker-plan-generation/v1",
        options = common)
    comparison_variant = FeatureVariant(
        joinpath(@__DIR__, "features", "bundle_comparison.jl");
        comparison_key = "perfchecker-bundle-comparison/v1")
    comparison = FeatureSpec(:bundle_comparison;
        description = "Compare two portable result bundles",
        variants = [comparison_variant], options = common)
    query = FeatureSpec(:query_engine;
        description = "Filter and order portable performance evidence",
        entrypoint = joinpath(@__DIR__, "features", "query_engine.jl"),
        comparison_key = "perfchecker-query-engine/v1",
        options = common)
    allocations = FeatureSpec(:bundle_comparison_allocations;
        workload = :bundle_comparison,
        description = "Attribute comparison allocations to PerfChecker source",
        backend = :profile_alloc,
        variants = [comparison_variant],
        options = Dict(:targets => ["PerfChecker"], :track => "none", :repeat => true))
    profile = FeatureSpec(:bundle_comparison_profile;
        workload = :bundle_comparison,
        description = "Capture comparison CPU stacks for interactive flame graphs",
        backend = :profile,
        variants = [comparison_variant],
        options = Dict(:targets => ["PerfChecker"], :track => "none", :repeat => true,
            :profile_seconds => 0.5, :profile_delay => 0.001))
    package = PackageSuite("PerfChecker";
        source = root,
        environment = joinpath(@__DIR__, "runner"),
        versions = VersionNumber[],
        include_dev = true,
        features = [plan_feature, comparison, query, allocations, profile])
    return SoftwareSuite(:perfchecker, [package];
        description = "PerfChecker engine performance without recursive orchestration")
end
