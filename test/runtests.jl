using TestItemRunner

@run_package_tests filter=ti->(
    get(ENV, "PERFCHECKER_TEST_PROFILE", "full") == "full" || :historical ∉ ti.tags)
