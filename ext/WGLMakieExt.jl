module WGLMakieExt

using Bonito
using Makie
using PerfChecker
import TestItems: @testitem
using WGLMakie

const RENDER_LOCK = ReentrantLock()
const HTML_CACHE = Dict{String, String}()
const MAX_CACHE_ENTRIES = 64

function _flame_plot_html(plot::PerfChecker.PerformancePlot)
    data_json = replace(PerfChecker._canonical_json(plot.data), "</" => "<\\/")
    title_json = PerfChecker._canonical_json(
        "$(plot.title) · $(plot.options["selected_version"])")
    value_label_json = PerfChecker._canonical_json(String(plot.options["value_label"]))
    allocation_json = plot.kind === :allocation_flamegraph ? "true" : "false"
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{color-scheme:light;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#111827;background:#f7f9fc}
*{box-sizing:border-box}body{margin:0;background:#f7f9fc}.flame-scroll{width:100%;height:100vh;min-height:34rem;overflow:auto;padding:.5rem}
#flame{display:block;width:100%;min-width:68rem;height:auto;background:white;border:1px solid #d8dee9;border-radius:.35rem}
.flame-frame{stroke:white;stroke-width:.8;cursor:help;outline:none}.flame-frame:hover,.flame-frame:focus{stroke:#111827;stroke-width:2}
.frame-label{font-size:11px;fill:#111827;pointer-events:none}.axis-label{font-size:12px;fill:#374151}.title{font-size:17px;font-weight:700;fill:#111827}.tick{font-size:10px;fill:#4b5563}.grid{stroke:#d1d5db;stroke-opacity:.5;stroke-width:1}.legend-title{font-size:13px;font-weight:700;fill:#111827}.legend-label,.note{font-size:11px;fill:#374151}
#tooltip{position:fixed;z-index:20;display:none;max-width:min(42rem,calc(100vw - 2rem));padding:.65rem .75rem;border-radius:.4rem;background:rgba(17,24,39,.96);color:white;font-size:12px;line-height:1.45;white-space:normal;overflow-wrap:anywhere;pointer-events:none;box-shadow:0 8px 28px rgba(0,0,0,.24)}
</style></head><body><div class="flame-scroll"><svg id="flame" role="img"></svg></div><div id="tooltip" role="tooltip"></div>
<script>
const DATA=$data_json;
const TITLE=$title_json;
const VALUE_LABEL=$value_label_json;
const ALLOCATION_ONLY=$allocation_json;
const NS="http://www.w3.org/2000/svg";
const svg=document.getElementById("flame"),tip=document.getElementById("tooltip");
const maximumDepth=Math.max(1,...DATA.map(item=>Number(item.depth)||1));
const rowHeight=18,marginLeft=82,marginRight=310,marginTop=54,marginBottom=62,svgWidth=1400;
const svgHeight=Math.max(620,marginTop+marginBottom+(maximumDepth+1)*rowHeight);
const plotWidth=svgWidth-marginLeft-marginRight;
svg.setAttribute("viewBox","0 0 "+svgWidth+" "+svgHeight);
svg.setAttribute("aria-label",TITLE+". Hover or focus a frame for its complete path and diagnostics.");
function element(name,attrs,text){const node=document.createElementNS(NS,name);for(const [key,value] of Object.entries(attrs||{}))node.setAttribute(key,String(value));if(text!==undefined)node.textContent=text;return node}
function hashColor(label){let hash=0;for(let i=0;i<label.length;i++)hash=(hash*31+label.charCodeAt(i))|0;return "hsl("+(Math.abs(hash)%360)+" 55% 68%)"}
const diagnosticColors={runtime_dispatch:"#c71431",inference_warning:"#7533b8",gc_event:"#f27f0c"};
function frameColor(item){return diagnosticColors[item.status]||hashColor(String(item.label))}
function number(value,digits=3){return Number(value||0).toLocaleString(undefined,{maximumFractionDigits:digits})}
function tooltipText(item){const lines=["<strong>"+escapeHtml(item.label)+"</strong>","Path: "+escapeHtml((item.path||[]).join(" → ")),"Share: "+number(item.percentage)+"%","Weight: "+number(item.value,6)+" "+escapeHtml(VALUE_LABEL)];if(Number(item.runtime_dispatch_value)>0)lines.push("Runtime dispatch: "+number(item.runtime_dispatch_percentage,2)+"% ("+number(item.runtime_dispatch_value,6)+" "+escapeHtml(VALUE_LABEL)+")");if(Number(item.gc_event_value)>0)lines.push("Garbage collection: "+number(item.gc_event_percentage,2)+"% ("+number(item.gc_event_value,6)+" "+escapeHtml(VALUE_LABEL)+")");if((item.inference_status||[]).length)lines.push("Julia inference: "+escapeHtml(item.inference_status.join(", ")));if((item.inferred_return_type||[]).length)lines.push("Inferred return: "+escapeHtml(item.inferred_return_type.join(" | ")));if((item.inference_status||[]).some(status=>["any","union","abstract"].includes(status)))lines.push("Inspect with @code_warntype or Cthulhu");return lines.join("<br>")}
function escapeHtml(value){return String(value).replace(/[&<>\"']/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;",'\"':"&quot;","'":"&#39;"}[char]))}
function showTip(item,event){tip.innerHTML=tooltipText(item);tip.style.display="block";const x=Math.min(event.clientX+14,window.innerWidth-tip.offsetWidth-10);const y=Math.min(event.clientY+14,window.innerHeight-tip.offsetHeight-10);tip.style.left=Math.max(8,x)+"px";tip.style.top=Math.max(8,y)+"px"}
svg.append(element("text",{x:svgWidth/2,y:29,"text-anchor":"middle",class:"title"},TITLE));
for(let tick=0;tick<=100;tick+=10){const x=marginLeft+plotWidth*tick/100;svg.append(element("line",{x1:x,x2:x,y1:marginTop,y2:svgHeight-marginBottom,class:"grid"}));svg.append(element("text",{x:x,y:svgHeight-marginBottom+19,"text-anchor":"middle",class:"tick"},tick))}
svg.append(element("text",{x:marginLeft+plotWidth/2,y:svgHeight-18,"text-anchor":"middle",class:"axis-label"},"share of captured "+VALUE_LABEL.toLowerCase()+" (%)"));
const yLabelPosition=marginTop+(svgHeight-marginTop-marginBottom)/2;const yLabel=element("text",{x:20,y:yLabelPosition,"text-anchor":"middle",class:"axis-label",transform:"rotate(-90 20 "+yLabelPosition+")"},"call stack depth");svg.append(yLabel);
DATA.forEach((item,index)=>{const x=marginLeft+plotWidth*Number(item.x0);const rectWidth=Math.max(.8,plotWidth*(Number(item.x1)-Number(item.x0)));const y=marginTop+(maximumDepth-Number(item.depth))*rowHeight;const rect=element("rect",{x,y,width:rectWidth,height:rowHeight-1,fill:frameColor(item),class:"flame-frame",tabindex:"0","data-index":index,"aria-label":String(item.label)+", "+number(item.percentage)+" percent"});rect.append(element("title",{},String(item.label)+"\\n"+(item.path||[]).join(" → ")));rect.addEventListener("pointermove",event=>showTip(item,event));rect.addEventListener("pointerleave",()=>tip.style.display="none");rect.addEventListener("focus",event=>{const box=rect.getBoundingClientRect();showTip(item,{clientX:box.left+box.width/2,clientY:box.top+box.height/2})});rect.addEventListener("blur",()=>tip.style.display="none");svg.append(rect);if(rectWidth>=52){svg.append(element("text",{x:x+rectWidth/2,y:y+12,"text-anchor":"middle",class:"frame-label"},String(item.label)))}});
const legendX=marginLeft+plotWidth+28,legendY=marginTop+18;
svg.append(element("text",{x:legendX,y:legendY-15,class:"legend-title"},"frame diagnostics"));
const legend=ALLOCATION_ONLY?[["#39a9b7","sampled allocation frame"]]:[["#39a9b7","sampled Julia frame"],[diagnosticColors.runtime_dispatch,"runtime dispatch"],[diagnosticColors.inference_warning,"non-concrete inferred return"],[diagnosticColors.gc_event,"garbage collection"]];
legend.forEach((entry,index)=>{const y=legendY+index*25;svg.append(element("rect",{x:legendX,y,width:18,height:18,fill:entry[0]}));svg.append(element("text",{x:legendX+26,y:y+13,class:"legend-label"},entry[1]))});
const notes=ALLOCATION_ONLY?["Width = share of allocated bytes.","Hover or focus every frame for its full path."]:["Red = observed dynamic dispatch.","Purple = cached non-concrete return inference.","Orange = garbage collection.","Hover or focus every frame for full diagnostics."];
notes.forEach((line,index)=>svg.append(element("text",{x:legendX,y:legendY+legend.length*25+22+index*17,class:"note"},line)));
</script></body></html>"""
end

"Render a PerformancePlot as a self-contained interactive WGLMakie document."
function PerfChecker.performance_plot_html(plot::PerfChecker.PerformancePlot)
    return lock(RENDER_LOCK) do
        key = PerfChecker._content_digest(PerfChecker.performance_plot_dict(plot))
        haskey(HTML_CACHE, key) && return HTML_CACHE[key]
        if plot.kind in (:allocation_flamegraph, :cpu_flamegraph, :wall_flamegraph)
            html = _flame_plot_html(plot)
            length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
                delete!(HTML_CACHE, first(keys(HTML_CACHE)))
            HTML_CACHE[key] = html
            return html
        end
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
        length(HTML_CACHE) >= MAX_CACHE_ENTRIES &&
            delete!(HTML_CACHE, first(keys(HTML_CACHE)))
        HTML_CACHE[key] = html
        return html
    end
end

@testitem "Interactive flame graph HTML" tags=[:unit, :plots, :wgl, :flamegraph] begin
    using PerfChecker
    using WGLMakie

    data = [Dict{String, Any}(
        "label" => "tiny", "path" => ["root", "tiny"], "depth" => 2,
        "x0" => 0.0, "x1" => 0.001, "value" => 1.0, "percentage" => 0.1,
        "status" => "inference_warning", "runtime_dispatch_value" => 0.0,
        "runtime_dispatch_percentage" => 0.0, "gc_event_value" => 0.0,
        "gc_event_percentage" => 0.0, "inference_status" => ["union"],
        "inferred_return_type" => ["Union{Int, String}"])]
    plot = PerfChecker.PerformancePlot("flame-test", :cpu_flamegraph,
        "CPU flame graph", "interactive flame graph", Dict{String, Any}(), data,
        Dict{String, Any}("selected_version" => "dev@1.0.0",
            "value_label" => "CPU samples"))
    html = performance_plot_html(plot)
    @test occursin("<svg id=\"flame\"", html)
    @test occursin("flame-frame", html)
    @test occursin("pointermove", html)
    @test occursin("Runtime dispatch", html)
    @test occursin("@code_warntype or Cthulhu", html)
    @test !occursin("<canvas", lowercase(html))
end

end
