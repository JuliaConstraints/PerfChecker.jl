using PerfChecker

using CompositionalNetworks
using ConstraintDomains

title = "Explore, Learn, and Compose"
path = normpath(joinpath(pathof(PerfChecker), "../perf"))
dependencies = [CompositionalNetworks, ConstraintDomains]
targets = [CompositionalNetworks]

domains = [domain([1, 2]) for i in 1:1]
pre_alloc() = foreach(_ -> explore_learn_compose(domains, allunique), 1:1)
alloc() = explore_learn_compose(domains, allunique)

alloc_check(title, dependencies, targets, pre_alloc, alloc; path)

for d in walkdir(@__DIR__), f in d[end]
    splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
end
rm(joinpath(path, "mallocs.csv"))
