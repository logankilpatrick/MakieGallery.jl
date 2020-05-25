function tourl(path)
    if Sys.iswindows()
        # THere might be a nicer way?
        # Anyways, this seems to be needed on windows
        if !startswith(path, "http")
            path = "file:///" * replace(path, "\\" => "/")
        end
    end
    return repr(path)
end

# NOTE: `save_media` is the function you want to overload
# if you want to create a Gallery with custom types.
# Simply overloading the function should do the trick
# and MakieGallery will take care of the rest.

function save_media(entry, x::Scene, path::String)
    path = joinpath(path, "image.png")
    save(FileIO.File(DataFormat{:PNG}, path), x) # work around FileIO bug for now
    [path]
end

function save_media(entry, x::String, path::String)
    out = joinpath(path, basename(x))
    if out != x
        mv(x, out, force = true)
    end
    [out]
end

function save_media(entry, x::AbstractPlotting.Stepper, path::String)
    # return a list of all file names
    images = filter(x-> endswith(x, ".png"), readdir(x.folder))
    return map(images) do img
        p = joinpath(x.folder, img)
        out = joinpath(path, basename(p))
        mv(p, out, force = true)
        out
    end
end

function save_media(entry, results::AbstractVector, path::String)
    paths = String[]
    for (i, res) in enumerate(results)
        # Only save supported results
        if res isa Union{Scene, String}
            img = joinpath(path, "image$i.png")
            save(FileIO.File(DataFormat{:PNG}, img), res) # work around FileIO
            push!(paths, img)
        end
    end
    paths
end

function save_media(example, events::RecordEvents, path::String)
    # the path is fixed at record time to be stored relative to the example
    epath = event_path(example, "")
    isfile(epath) || error("Can't find events for example: $(example.unique_name). Please run `record_example_events()`")
    # the current path of RecordEvents is where we now actually want to store the video
    video_path = joinpath(path, "video.mp4")
    record(events.scene, video_path) do io
        replay_events(events.scene, epath) do
            recordframe!(io)
        end
    end
    return [video_path]
end

"""
    embed_image(path::AbstractString)
Returns the html to embed an image
"""
function embed_image(path::AbstractString, alt = "")
    if splitext(path)[2] == "pdf"
        return """
            <iframe src=$(tourl(path))></iframe>
        """
    end
    """
    <img src=$(tourl(path)) alt=$(repr(alt))>
    """
end

"""
    embed_video(path::AbstractString)

Generates a html formatted string for embedding video into Documenter Markdown files
(since `Documenter.jl` doesn't support directly embedding mp4's using ![]() syntax).
"""
function embed_video(path::AbstractString, alt = "")
    """
    <video controls autoplay loop muted>
      <source src=$(tourl(path)) type="video/mp4">
      Your browser does not support mp4. Please use a modern browser like Chrome or Firefox.
    </video>
    """
end

"""
Embeds the most common media types as html
"""
function embed_media(path::String, alt = "")
    file, ext = splitext(path)
    if ext in (".png", ".jpg", ".jpeg", ".JPEG", ".JPG", ".gif", ".pdf", ".svg")
        return embed_image(path, alt)
    elseif ext == ".mp4"
        return embed_video(path, alt)
    else
        error("Unknown media extension: $ext with path: $path")
    end
end


"""
Embeds a vector of media files as HTML
"""
function embed_media(io::IO, paths::AbstractVector{<: AbstractString}, caption = "")
    for (i, path) in enumerate(paths)
        occursin("thumb", path) && continue
        println(io, """
        <div style="display:inline-block">
            <p style="display:inline-block; text-align: center">
                $(embed_media(path, caption))
            </p>
        </div>
        """)
    end
end

"""
Replaces raw html code nodes with an actual RawHTML node.
"""
function preprocess!(md)
    map!(md.content, md.content) do c
        if c isa Markdown.Code && c.language == "@raw html"
            Documenter.Documents.RawHTML(c.code)
        else
            c
        end
    end
    md
end

function md2html(md_path; stylesheets = Vector{String}[])
    open(joinpath(dirname(md_path), "index.html"), "w") do io
        md = preprocess!(Markdown.parse_file(md_path))
        hio = IOBuffer(write=true, read=true)
        for sheetref in stylesheets
            println(hio, "<link rel=\"stylesheet\" href=\"$(sheetref)\">")
        end
        println(io, """
        <!doctype html>
        <html>
          <head>
            <meta charset="UTF-8">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/JuliaDocs/Documenter.jl/assets/html/documenter.css">
            $(String(take!(hio)))
          </head>
          <body>
        """)
        println.(Ref(io), string.(HTMLWriter.mdconvert(md)))
        println(io, """
            </body>
            </html>
            """
        )
    end
end

"""
    save_markdown(mdpath::String, example::CellEntry, media::Vector{String})

Creates a Markdown representation from an example at `mdpath`.
`media` is a vector of media output files belonging to the example
"""
function save_markdown(mdpath::String, example::CellEntry, media::Vector{String})
    # src = example2source(
    #     example,
    #     scope_start = "",
    #     scope_end = "",
    #     indent = "",
    #     outputfile = (entry, ending)-> string("output", ending)
    # )
    src = example2source(
        example,
        scope_start = "",
        scope_end = "",
        indent = "",
        outputfile = (entry, ending)-> string("output", ending)
    )
    open(mdpath, "w") do io
        println(io, "## ", example.title, "\n")
        println(io, "```julia\n$src\n```")
        println(io, "```@raw html\n")
        embed_media(io, media)
        println(io, "```")
    end
end

"""
    save_highlighted_markdown(path::String, example::CellEntry, media::Vector{String};
                                highlighter = Highlights.Themes.DefaultTheme)
Creates a Markdown representation from an example at `mdpath`.
`media` is a vector of media output files belonging to the example
"""
function save_highlighted_markdown(
                                path::String, example::CellEntry, media::Vector{String},
                                highlighter = Highlights.Themes.DefaultTheme;
                                print_toplevel = true
                            )

    src = example2source(
        example,
        scope_start = "",
        scope_end = "",
        indent = "",
        outputfile = (entry, ending)-> string("output", ending),
        print_toplevel = print_toplevel,
        print_backends = true
    )
    hio = IOBuffer(read = true, write = true)
    highlight(hio, MIME("text/html"), src, Highlights.Lexers.JuliaLexer, highlighter)
    html = String(take!(hio))
    open(path, "w") do io
        println(io, "## ", example.title, "\n")
        println(io, "```@raw html\n$html\n```")
        println(io, "```@raw html\n")
        embed_media(io, media)
        println(io, "```")
    end

end

const last_evaled = Ref{Int}()

"""
    set_last_evaled!(database_idx::Int)
Set's last evaled for resume
"""
function set_last_evaled!(database_idx::Int)
    last_evaled[] = database_idx - 1
    database_idx
end

"""
    set_last_evaled!(database_idx::Int)
Set's last evaled for resume
"""
function set_last_evaled!(unique_name::Symbol)
    idx = findfirst(e-> e.unique_name == unique_name, database)
    if idx === nothing
        error("Unique name $unique_name not found in database")
    end
    last_evaled[] = idx - 1 # minus one, because record_example will start at idx + 1
end

backend_reset_theme!(; kwargs...) = AbstractPlotting.set_theme!(; kwargs...)
# for Plots: default(; kwargs...)

"""
    record_examples(folder = ""; resolution = (500, 500), resume = false)

Records all examples in the database. If error happen, you can fix them and
start record with `resume = true`, to start at the last example that errored.
"""
function record_examples(
        folder = "";
        resolution = (500, 500), resume::Union{Bool, Integer} = false,
        generate_thumbnail = false, display = false,
        display_output_toplevel = true
    )

    function output_path(entry, ending)
        joinpath(folder, "tmp", string(entry.unique_name, ending))
    end
    ispath(folder) || mkpath(folder)
    ispath(joinpath(folder, "tmp")) || mkdir(joinpath(folder, "tmp"))
    result = []
    start = if resume isa Int
        start = resume
    elseif (resume isa Bool) && resume && last_evaled[] >= 0 && last_evaled[] < length(database)
        last_evaled[] + 1
    else
        1
    end
    @info("starting from index $start")
    backend_reset_theme!(resolution = resolution)
    AbstractPlotting.inline!(true)
    @testset "Full Gallery recording" begin
        eval_examples(outputfile = output_path, start = start) do example, value
            uname = example.unique_name
            @testset "$(example.title)" begin
                try
                    subfolder = joinpath(folder, string(uname))
                    outfolder = joinpath(subfolder, "media")
                    ispath(outfolder) || mkpath(outfolder)
                    save_media(example, value, outfolder)
                    push!(result, subfolder)
                    set_last_evaled!(uname)
                    backend_reset_theme!(resolution = resolution) # reset before next example
                    AbstractPlotting.inline!(true)
                    @test true
                    if generate_thumbnail && !isfile(outfolder) && ispath(outfolder)
                        sample = joinpath(outfolder, first(readdir(outfolder)))
                        MakieGallery.generate_thumbnail(sample, joinpath(outfolder, "thumb.png"))
                    end
                catch e
                    @warn "Error thrown when evaluating $(example.title)" exception=CapturedException(e, Base.catch_backtrace())
                    @test false
                end
            end
        end
    end
    rm(joinpath(folder, "tmp"), recursive = true, force = true)
    gallery_from_recordings(folder, joinpath(folder, "index.html"); print_toplevel = display_output_toplevel)
    result
end

"""
    gallery_from_recordings(
        folder::String,
        html_out::String = abspath(joinpath(pathof(MakieGallery), "..", "..", "index.html"));
        tags = [
            string.(AbstractPlotting.atomic_function_symbols)...,
            "interaction",
            "record",
            "statsmakie",
            "vbox",
            "layout",
            "legend",
            "colorlegend",
            "vectorfield",
            "poly",
            "camera",
            "recipe",
            "theme",
            "annotations"
        ],
        hltheme = Highlights.Themes.DefaultTheme
    )
Creates a Gallery in `html_out` from already recorded examples in `folder`.
"""
function gallery_from_recordings(
        folder::String,
        html_out::String = abspath(joinpath(pathof(MakieGallery), "..", "..", "index.html"));
        tags = [
            string.(AbstractPlotting.atomic_function_symbols)...,
            "interaction",
            "record",
            "statsmakie",
            "vbox",
            "layout",
            "legend",
            "colorlegend",
            "vectorfield",
            "poly",
            "camera",
            "recipe",
            "theme",
            "annotations",
            "layout",
            "grid",
            "geomakie"
        ],
        hltheme = Highlights.Themes.DefaultTheme,
        print_toplevel = true
    )

    items = map(MakieGallery.database) do example
        base_path = joinpath(folder, string(example.unique_name))
        media_path = joinpath(base_path, "media")
        media = master_url.(abspath(folder), joinpath.(abspath(media_path), readdir(media_path)))
        mdpath = joinpath(base_path, "index.md")
        save_highlighted_markdown(mdpath, example, media, hltheme; print_toplevel = print_toplevel)
        md2html(mdpath; stylesheets = [relpath(joinpath(dirname(html_out), "syntaxtheme.css"), base_path)])
        MediaItem(base_path, example)
    end
    open(html_out, "w") do io
        println(io, create_page(items, tags))
    end
    open(joinpath(dirname(html_out), "syntaxtheme.css"), "w") do io
        stylesheet(io, MIME("text/css"), hltheme)
    end
end




function rescale_image(path::AbstractString, target_path::AbstractString, sz::Int = 200)
    !isfile(path) && error("Input argument must be a file!")
    img = FileIO.load(path)
    # calculate new image size `newsz`
    (height, width) = size(img)
    (scale_height, scale_width) = sz ./ (height, width)
    scale = min(scale_height, scale_width)
    newsz = round.(Int, (height, width) .* scale)

    # filter image + resize image
    gaussfactor = 0.4
    σ = map((o,n) -> gaussfactor*o/n, size(img), newsz)
    kern = KernelFactors.gaussian(σ)   # from ImageFiltering
    imgf = ImageFiltering.imfilter(img, kern, NA())
    newimg = ImageTransformations.imresize(imgf, newsz)
    # save image
    FileIO.save(target_path, newimg)
end


"""
    generate_thumbnail(path::AbstractString, target_path, thumb_size::Int = 200)

Generates a (proportionally-scaled) thumbnail with maximum side dimension `sz`.
`sz` must be an integer, and the default value is 200 pixels.
"""
function generate_thumbnail(path, thumb_path, thumb_size = 128)
    if any(ext-> endswith(path, ext), (".png", ".jpeg", ".jpg"))
        rescale_image(path, thumb_path, thumb_size)
    elseif any(ext-> endswith(path, ext), (".gif", ".mp4", ".webm"))
        seektime = get_video_duration(path) / 2
        FFMPEG.ffmpeg_exe(`-loglevel quiet -ss $seektime -i $path -vframes 1 -vf "scale=$(thumb_size):-2" -y -f image2 $thumb_path`)
    else
        @warn("Unsupported return file format in $path")
    end
end

function generate_thumbnails(media_root)
    for folder in readdir(media_root)
        media = joinpath(media_root, folder, "media")
        if !isfile(media) && ispath(media)
            isempty(readdir(media)) && error("Media $(media) doesn't contain anything")
            sample = joinpath(media, first(readdir(media)))
            generate_thumbnail(sample, joinpath(media, "thumb.png"))
        end
    end
end

"""
Embedds all produced media in one big html file
"""
function generate_preview(media_root, path = joinpath(@__DIR__, "preview.html"))
    open(path, "w") do io
        for folder in readdir(media_root)
            media = joinpath(media_root, folder, "media")
            if !isfile(media) && ispath(media)
                medias = joinpath.(media, readdir(media))
                println(io, "<h1> $folder </h1>")
                MakieGallery.embed_media(io, medias)
            end
        end
    end
end
