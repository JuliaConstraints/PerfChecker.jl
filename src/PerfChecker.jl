module PerfChecker

# SECTION - Imports
import Base.Sys: CPUinfo, CPU_NAME, cpu_info, WORD_SIZE
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo
import CpuId: simdbytes, cpucores, cputhreads, cputhreads_per_core
import CSV
import Dates
import Downloads
import JSON
import Malt: remote_eval_wait, Worker, remote_eval_fetch, stop, fetch
import Pkg
import Pkg.Types: PackageSpec, Context
import Profile
import Random

# Extension entry points. Their implementations are loaded only when the
# corresponding optional dependency is present.
function drwatson_run_suite end
function documenter_makedocs end
function documenter_page end
function documenter_vitepress_makedocs end
function freeze_propcheck_corpus end
function prepare_pluto_dashboard end
function terminal_plot end
import SHA
import TOML: parse
import TestItems: @testitem
import TypedTables: Table
import UUIDs: UUID, uuid4, uuid5

# SECTION - Exports
export @check
export FeatureSpec
export FeatureVariant
export FeatureRun
export ExternalCommandSpec
export BundleComparison
export VersionComparison
export PackageSuite
export PlannedFeatureRun
export SoftwareSuite
export SoftwareSuiteResult
export RunBundle
export SuiteJob
export SuitePlan
export VersionWindow
export check_to_metadata_csv
export bundle_passed
export cancel_suite!
export bundle_dict
export comparison_dict
export comparison_passed
export compare_bundles
export compare_suite_versions
export performance_figure
export performance_plot
export performance_plot_dict
export performance_plot_html
export plot_catalog
export external_command_dict
export checkres_to_boxplots
export checkres_to_pie
export checkres_to_scatterlines
export csv_to_table
export drwatson_parameters
export drwatson_produce_or_load
export drwatson_run_suite
export drwatson_savename
export documenter_makedocs
export documenter_page
export documenter_vitepress_makedocs
export find_by_tags
export freeze_supposition_corpus
export freeze_propcheck_corpus
export get_versions
export launch_pluto_dashboard
export prepare_pluto_dashboard
export launch_suite
export load_software_suite
export plan_suite
export planned_run_id
export PerfConfig
export perf_setup
export register_oxygen_routes!
export read_property_corpus
export read_provider_result
export read_run_bundle
export list_run_bundles
export run_external_command
export run_suite
export run_suite_file
export run_studio_agent
export saveplot
export serve_suite
export select_suite_plan
export filter_suite_plan
export configure_suite_repl
export print_suite_plan
export run_suite_repl
export studio_token_authenticator
export write_folded_profile
export write_pprof_profile
export write_speedscope_profile
export summary_table
export suite_dashboard
export suite_dict
export suite_job_status
export suite_job_dict
export suite_job_progress
export suite_passed
export suite_plan_dict
export suite_summary
export suite_version_series
export table_to_csv
export table_to_pie
export terminal_plot
export to_table
export write_suite_json
export write_run_bundle
export write_comparison_json
export write_comparison_markdown
export write_version_comparison_json
export write_version_comparison_markdown
export write_version_series_json
export version_comparison_dict
export version_comparison_passed
export write_suite_bundle
export write_suite_junit
export write_suite_markdown
export write_suite_notebook
export write_suite_reports
export write_template
export write_property_corpus
export wait_suite

# SECTION - Includes
include("init.jl")
include("hwinfo.jl")
include("config.jl")
include("checker_results.jl")
include("summary.jl")
include("utils.jl")
include("csv.jl")
include("versions.jl")
include("templates.jl")
include("corpus.jl")
include("check.jl")
include("alloc.jl")
include("profile_allocs.jl")
include("profile.jl")
include("network.jl")
include("suites.jl")
include("repl.jl")
include("protocol.jl")
include("profile_exports.jl")
include("compare.jl")
include("version_compare.jl")
include("plots.jl")

end
