using PerfChecker

function perf_setup()
    root = pkgdir(PerfChecker)
    feature = FeatureSpec(:noop;
        description = "Synthetic feature used to measure planning",
        entrypoint = @__FILE__,
        comparison_key = "perfchecker-self-plan-noop/v1")
    package = PackageSuite("PerfChecker";
        source = root,
        environment = joinpath(root, "perf", "runner"),
        versions = [v"0.2.4"],
        include_dev = false,
        features = [feature])
    return SoftwareSuite(:perfchecker_planning, [package])
end

function perf_workload(suite)
    plan_suite(suite;
        profile = :release, version_provider = _ -> [v"0.2.4"])
end
