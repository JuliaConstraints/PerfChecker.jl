module WGLMakieExt

using Bonito
using Makie
using PerfChecker
using WGLMakie

const RENDER_LOCK = ReentrantLock()
const HTML_CACHE = Dict{String, String}()
const MAX_CACHE_ENTRIES = 64

"Render a PerformancePlot as a self-contained interactive WGLMakie document."
function PerfChecker.performance_plot_html(plot::PerfChecker.PerformancePlot)
    return lock(RENDER_LOCK) do
        key = PerfChecker._content_digest(PerfChecker.performance_plot_dict(plot))
        haskey(HTML_CACHE, key) && return HTML_CACHE[key]
        WGLMakie.activate!(; resize_to = :parent, framerate = 24)
        figure = PerfChecker.performance_figure(plot)
        app = Bonito.App() do
            Bonito.DOM.div(
                WGLMakie.WithConfig(figure; resize_to = :parent),
                style = Bonito.Styles(
                    "width" => "100%", "height" => "100vh", "min-height" => "34rem",
                    "overflow" => "hidden", "background" => "#f7f9fc"))
        end
        io = IOBuffer()
        session = Bonito.export_static(io, app)
        close(session)
        html = String(take!(io))
        length(HTML_CACHE) >= MAX_CACHE_ENTRIES && delete!(HTML_CACHE, first(keys(HTML_CACHE)))
        HTML_CACHE[key] = html
        return html
    end
end

end
