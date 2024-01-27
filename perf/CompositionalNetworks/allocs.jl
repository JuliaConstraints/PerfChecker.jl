using PerfChecker, PrettyTables

t = @check :alloc Dict(:path => @__DIR__, :targets => ["CompositionalNetworks"]) begin
    using CompositionalNetworks, ConstraintDomains
    end begin
        domains = [domain([1, 2]) for i in 1:1]
        pre_alloc() = foreach(_ -> explore_learn_compose(domains, allunique), 1:1)
        explore_learn_compose(domains, allunique)
    end

pretty_table(t |> to_table)
