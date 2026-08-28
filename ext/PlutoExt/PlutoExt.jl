module PlutoExt

using PerfChecker
using Pluto

function PerfChecker.launch_pluto_dashboard(path::AbstractString; kwargs...)
    notebook = abspath(String(path))
    isfile(notebook) || throw(ArgumentError("Pluto notebook does not exist: $notebook"))
    return Pluto.run(; notebook, kwargs...)
end

end
