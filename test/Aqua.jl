@testset "Aqua.jl" begin
	import Aqua
	import PerfChecker

	# TODO: Fix the broken tests and remove the `broken = true` flag
	Aqua.test_all(
		PerfChecker;
		ambiguities = (broken = true,),
		deps_compat = false,
		piracies = (broken = false,)
	)

	@testset "Ambiguities: PatternFolds" begin
		Aqua.test_ambiguities(PerfChecker)
	end

	@testset "Piracies: PatternFolds" begin
		Aqua.test_piracies(PerfChecker;
		# treat_as_own = [Intervals.Interval]
		)
	end

	@testset "Dependencies compatibility (no extras)" begin
		Aqua.test_deps_compat(PerfChecker;
			check_extras = false,
			ignore = [:Distributed, :Pkg, :Profile, :TOML]
		)
	end
end
