using TestItemRunner

profile = get(ENV, "PERFCHECKER_TEST_PROFILE", "full")
selected_tags = Set(Symbol.(filter(!isempty,
    split(get(ENV, "PERFCHECKER_TEST_TAGS", ""), ','))))

@run_package_tests filter=ti->(
    (profile == "full" || :historical ∉ ti.tags) &&
    (isempty(selected_tags) || !isempty(selected_tags ∩ Set(ti.tags))))
