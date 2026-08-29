module PlutoExt

using PerfChecker
using Pluto

function PerfChecker.launch_pluto_dashboard(path::AbstractString; kwargs...)
    notebook = abspath(String(path))
    isfile(notebook) || throw(ArgumentError("Pluto notebook does not exist: $notebook"))
    return Pluto.run(; notebook, kwargs...)
end

function PerfChecker.prepare_pluto_dashboard(path::AbstractString;
        suite_path = nothing, factory::Symbol = :build_suite)
    destination = abspath(String(path))
    PerfChecker.write_suite_notebook(destination; suite_path, factory)
    return destination
end

end
