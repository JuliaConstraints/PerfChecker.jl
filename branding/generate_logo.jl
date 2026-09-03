using Luxor

const BRANDING_ROOT = @__DIR__
const EXPORT_ROOT = joinpath(BRANDING_ROOT, "exports")
const REPOSITORY_ROOT = dirname(BRANDING_ROOT)

const INK = "#071014"
const PAPER = "#F7FAFC"
const TEAL = "#389826"
const CYAN = "#4063D8"
const BLUE = "#4063D8"
const VIOLET = "#9558B2"
const CORAL = "#CB3C33"

function rounded_rectangle(center::Point, width, height, radius, action::Symbol)
    x0, x1 = center.x - width / 2, center.x + width / 2
    y0, y1 = center.y - height / 2, center.y + height / 2
    k = 0.5522847498307936
    newpath()
    move(Point(x0 + radius, y0))
    line(Point(x1 - radius, y0))
    curve(Point(x1 - radius + k * radius, y0),
        Point(x1, y0 + radius - k * radius), Point(x1, y0 + radius))
    line(Point(x1, y1 - radius))
    curve(Point(x1, y1 - radius + k * radius),
        Point(x1 - radius + k * radius, y1), Point(x1 - radius, y1))
    line(Point(x0 + radius, y1))
    curve(Point(x0 + radius - k * radius, y1),
        Point(x0, y1 - radius + k * radius), Point(x0, y1 - radius))
    line(Point(x0, y0 + radius))
    curve(Point(x0, y0 + radius - k * radius),
        Point(x0 + radius - k * radius, y0), Point(x0 + radius, y0))
    closepath()
    action === :fill ? fillpath() : strokepath()
end

function stroke_segment(a::Point, b::Point, color, width)
    sethue(color)
    setline(width)
    line(a, b, :stroke)
end

function mark_series(points, color, label)
    sethue(color)
    setline(9)
    setlinecap("round")
    setlinejoin("round")
    move(first(points))
    for point in Iterators.drop(points, 1)
        line(point)
    end
    strokepath()
    for point in points[1:(end - 1)]
        circle(point, 7, :fill)
    end
    endpoint = last(points)
    setline(7)
    line(endpoint, endpoint + Point(20, 0), :stroke)
    fontface("Arial Bold")
    fontsize(34)
    text(label, endpoint + Point(30, 1); halign = :left, valign = :middle)
end

"Draw the canonical PerfChecker comparison-plot mark on a 1024-unit grid."
function draw_mark(; panel = true, monochrome = false, dark = false)
    paper = dark ? INK : "#FFFFFF"
    ink = dark ? PAPER : INK
    colors = monochrome ? (PAPER, PAPER, PAPER, PAPER) : (TEAL, CYAN, VIOLET, CORAL)

    if panel
        sethue(paper)
        circle(O, 420, :fill)
    end
    setlinecap("round")
    segments = ((colors[4], -0.48pi, -0.03pi),
        (colors[1], 0.02pi, 0.47pi),
        (colors[2], 0.52pi, 0.97pi),
        (colors[3], 1.02pi, 1.47pi))
    for (color, start, stop) in segments
        sethue(color)
        setline(16)
        arc(O, 402, start, stop, :stroke)
    end

    xaxis_y = 174
    left_x = -292
    sethue(ink)
    setline(6)
    line(Point(left_x, -205), Point(left_x, xaxis_y), :stroke)
    line(Point(left_x, xaxis_y), Point(304, xaxis_y), :stroke)

    xpositions = (-230, -90, 50, 170)
    labels = ("v1.0", "v1.1", "dev", "a13f")
    for (x, label) in zip(xpositions, labels)
        sethue(ink)
        setline(5)
        line(Point(x, xaxis_y - 8), Point(x, xaxis_y + 9), :stroke)
        fontface(label in ("dev", "a13f") ? "Arial Bold" : "Arial")
        fontsize(41)
        text(label, Point(x, xaxis_y + 48); halign = :center, valign = :middle)
    end

    speed = (Point(-230, -170), Point(-90, -142), Point(50, -148), Point(170, -122))
    allocations = (Point(-230, -122), Point(-90, -95), Point(50, -80), Point(170, -62))
    gc = (Point(-230, -72), Point(-90, -52), Point(50, -34), Point(170, -8))
    network = (Point(-230, -22), Point(-90, 1), Point(50, 16), Point(170, 45))
    coverage = (Point(-230, 28), Point(-90, 49), Point(50, 70), Point(170, 105))
    mark_series(speed, colors[2], "speed")
    mark_series(allocations, colors[1], "alloc")
    mark_series(gc, colors[3], "GC")
    mark_series(network, colors[4], "network")
    mark_series(coverage, ink, "coverage")
    return nothing
end

function render_mark(path::AbstractString; size::Integer = 1024)
    Drawing(size, size, path)
    origin()
    scale(size / 1024)
    draw_mark()
    finish()
    return path
end

function render_lockup(path::AbstractString; dark::Bool = false)
    width, height = 1900, 640
    Drawing(width, height, path)
    origin()
    background(dark ? INK : "transparent")
    gsave()
    translate(-620, 0)
    scale(0.52)
    draw_mark(; dark)
    grestore()

    sethue(dark ? PAPER : INK)
    fontface("Arial Bold")
    fontsize(184)
    text("PerfChecker", Point(-270, 24); halign = :left, valign = :middle)
    sethue(VIOLET)
    text(".jl", Point(755, 24); halign = :left, valign = :middle)
    finish()
    return path
end

function render_preview(path::AbstractString)
    width, height = 1800, 1120
    Drawing(width, height, path)
    origin()
    background(PAPER)

    sethue(INK)
    fontface("Arial Bold")
    fontsize(46)
    text("PerfChecker.jl — canonical comparison mark", Point(-820, -485);
        halign = :left, valign = :middle)
    sethue("#5D6870")
    fontface("Arial")
    fontsize(25)
    text("discrete targets · comparable metrics · versioned evidence",
        Point(-820, -432); halign = :left, valign = :middle)

    gsave()
    translate(-500, 40)
    scale(0.62)
    draw_mark()
    grestore()

    sethue(INK)
    fontface("Arial Bold")
    fontsize(112)
    text("PerfChecker", Point(-80, -70); halign = :left, valign = :middle)
    sethue(VIOLET)
    text(".jl", Point(550, -70); halign = :left, valign = :middle)
    sethue("#42515A")
    fontface("Arial")
    fontsize(31)
    text("Measure what actually runs", Point(-75, 12);
        halign = :left, valign = :middle)

    labels = ((CYAN, "speed"), (TEAL, "alloc"),
        (VIOLET, "GC"), (CORAL, "network"), ("#5D6870", "coverage"))
    for (index, (color, label)) in enumerate(labels)
        x = -105 + (index - 1) * 184
        sethue(color)
        rounded_rectangle(Point(x, 125), 152, 48, 24, :fill)
        sethue(index == 2 ? INK : PAPER)
        fontface("Arial Bold")
        fontsize(20)
        text(label, Point(x, 128); halign = :center, valign = :middle)
    end

    sethue("#DCE5EA")
    setline(2)
    line(Point(-75, 205), Point(770, 205), :stroke)
    sethue(INK)
    fontface("Arial Bold")
    fontsize(25)
    text("SMALL-SIZE CHECK", Point(-75, 258); halign = :left, valign = :middle)
    for (index, size) in enumerate((128, 64, 32))
        gsave()
        x = 85 + (index - 1) * 210
        translate(x, 375)
        scale(size / 1024)
        draw_mark()
        grestore()
        sethue("#5D6870")
        fontface("Arial")
        fontsize(20)
        text("$(size) px", Point(x, 475); halign = :center, valign = :middle)
    end

    finish()
    return path
end

mkpath(EXPORT_ROOT)
outputs = [
    render_mark(joinpath(EXPORT_ROOT, "perfchecker-mark.svg")),
    render_mark(joinpath(EXPORT_ROOT, "perfchecker-mark.png")),
    render_lockup(joinpath(EXPORT_ROOT, "perfchecker-lockup-light.svg")),
    render_lockup(joinpath(EXPORT_ROOT, "perfchecker-lockup-dark.svg"); dark = true),
    render_preview(joinpath(EXPORT_ROOT, "perfchecker-preview.png")),
    render_mark(joinpath(REPOSITORY_ROOT, "docs", "src", "public", "assets",
        "perfchecker.svg")),
    render_mark(joinpath(REPOSITORY_ROOT, "editors", "vscode", "media",
            "perfchecker.png");
        size = 256)
]

foreach(println, outputs)
