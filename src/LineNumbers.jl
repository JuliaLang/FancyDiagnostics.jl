"""
    SourceText(code; filename="none")

Source code in textural form
"""
struct SourceText # TODO: Make this an AbstractString?
    data::Vector{UInt8}
    filename::String
end

SourceText(code::Vector{UInt8}, filename) = SourceText(code, filename)
SourceText(code::AbstractString, filename) = SourceText(Vector{UInt8}(String(code)), filename)

SourceText(;     filename="none") = SourceText(read(filename), filename)
SourceText(code; filename="none") = SourceText(code, filename)

function Base.show(io::IO, text::SourceText)
    buf = IOBuffer(text.data)
    println(io, "SourceText(\"\"\"")
    for i = 1:20
        print(io, readline(buf, keep=true))
    end
    if !eof(buf)
        println(io, "…")
    end
    print(io, "\"\"\"; filename=$(repr(text.filename)))")
end

Base.getindex(text::SourceText, r::AbstractUnitRange) = String(text.data[r])

"""
    IndexedSource(text::SourceText)

Source text carrying an index for the start of each line.
"""
struct IndexedSource <: AbstractVector{String}
    text::SourceText
    # The byte index for the character at the start of each line.
    line_starts::Vector{Int}
end

function IndexedSource(text::SourceText)
    buf = IOBuffer(text.data)
    line_starts = Int[1]
    while !eof(buf)
        line = readuntil(buf, '\n', keep=true)
        push!(line_starts, position(buf)+1)
    end
    IndexedSource(text, line_starts)
end

function line_start(src::IndexedSource, index, delta_lines=0)
    if length(src.line_starts) == 1
        return 0
    end
    line = searchsortedlast(src.line_starts, index)
    src.line_starts[clamp(line + delta_lines, 1, length(src.line_starts))]
end

function line_end(src::IndexedSource, index, delta_lines=0)
    if length(src.line_starts) == 1
        return 0
    end
    line = searchsortedlast(src.line_starts, index)
    src.line_starts[clamp(line + 1 + delta_lines, 1, length(src.line_starts))]-1
end

function source_location(src::IndexedSource, index)
    if length(src.line_starts) == 1
        # Zero lines
        return (1,1)
    end
    line = searchsortedlast(src.line_starts, index)
    if line == length(src.line_starts)
        line -= 1
        partial_line = src[line]
    else
        partial_line = String(src.text.data[src.line_starts[line]:index])
    end
    col = textwidth(partial_line)
    (line,col)
end

function source_line(src::IndexedSource, index)
    first(source_location(src, index))
end

function Base.summary(io::IO, src::IndexedSource)
    print(io, "IndexedSource for $(repr(src.text.filename)) with $(length(src)) lines")
end

function intersect_lines(src::IndexedSource, rng::AbstractUnitRange)
    lines = source_line(src, first(rng)):source_line(src, last(rng))
    line_start_inds = src.line_starts[lines]
    line_end_inds = src.line_starts[lines .+ 1] .- 1
    [intersect(rng, s:e) for (s,e) in zip(line_start_inds, line_end_inds)]
end

Base.size(src::IndexedSource) = (length(src.line_starts)-1,)

function Base.getindex(src::IndexedSource, line::Int)
    if line == length(src.line_starts)
        # Allow line-off-the-end as error may occur at EOF
        # TODO: Is there a neater way?
        return ""
    end
    i1 = src.line_starts[line]
    i2 = src.line_starts[line+1] - 1
    return String(src.text.data[i1:i2])
end

