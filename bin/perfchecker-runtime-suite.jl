import Pkg

function runtime_values(name::String)
    prefix = "--$name="
    return [argument[(length(prefix) + 1):end]
            for argument in ARGS if startswith(argument, prefix)]
end

function runtime_option(name::String, default::String = "")
    matches = runtime_values(name)
    length(matches) <= 1 || error("--$name may be supplied only once")
    return isempty(matches) ? default : only(matches)
end

perfchecker_project_option = runtime_option("perfchecker-project")
suite_option = runtime_option("suite")
isempty(perfchecker_project_option) && error("--perfchecker-project=path is required")
isempty(suite_option) && error("--suite=path is required")
perfchecker_project = abspath(perfchecker_project_option)
suite = abspath(suite_option)
reports = abspath(runtime_option("reports"))
profile = Symbol(runtime_option("profile", "ci"))
factory = Symbol(runtime_option("factory", "build_suite"))

ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
Pkg.develop(path = perfchecker_project; io = devnull)
Pkg.instantiate(; io = devnull)

using PerfChecker

for package in runtime_values("backend-package")
    Core.eval(Main, Expr(:import, Expr(:., Symbol(package))))
end

result = run_suite_file(suite; reports, profile, factory, strict = false)
println("PerfChecker ", result.plan.suite.id, ": ",
    suite_passed(result) ? "PASS" : "FAIL", " (", length(result.runs), " runs)")
suite_passed(result) || exit(1)
