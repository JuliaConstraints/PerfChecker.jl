@testitem "Public protocol schemas" tags=[:unit, :protocol, :schemas] begin
    using JSON
    using PerfChecker

    expected = [
        "perfchecker-agent-evidence-v1.schema.json",
        "perfchecker-bundle-integrity-v1.schema.json",
        "perfchecker-capabilities-v1.schema.json",
        "perfchecker-comparison-v1.schema.json",
        "perfchecker-compatibility-report-v1.schema.json",
        "perfchecker-dependency-evidence-v1.schema.json",
        "perfchecker-document-block-v1.schema.json",
        "perfchecker-isolated-network-result-v1.schema.json",
        "perfchecker-julia-investigation-v1.schema.json",
        "perfchecker-julia-runtime-campaign-v1.schema.json",
        "perfchecker-julia-runtime-spec-v1.schema.json",
        "perfchecker-network-isolation-spec-v1.schema.json",
        "perfchecker-progress-v1.schema.json",
        "perfchecker-provider-result-v1.schema.json",
        "perfchecker-query-result-v1.schema.json",
        "perfchecker-query-v1.schema.json",
        "perfchecker-run-bundle-v1.schema.json",
        "perfchecker-suite-job-v1.schema.json",
        "perfchecker-suite-plan-v1.schema.json",
        "perfchecker-suite-result-v1.schema.json",
        "perfchecker-ui-config-v1.schema.json",
        "perfchecker-version-comparison-v1.schema.json",
        "perfchecker-version-series-v1.schema.json"]
    root = joinpath(pkgdir(PerfChecker), "schemas")
    actual = sort(filter(name -> endswith(name, ".schema.json"), readdir(root)))
    @test actual == expected
    for name in actual
        schema = JSON.parsefile(joinpath(root, name); use_mmap = false)
        @test schema["\$schema"] == "https://json-schema.org/draft/2020-12/schema"
        @test startswith(
            schema["\$id"], "https://mirage-interactive-fr.github.io/PerfChecker.jl/")
        @test schema["type"] == "object"
    end
end
