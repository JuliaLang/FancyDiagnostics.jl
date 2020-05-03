"""
    SourceText(code; filename="none")

A source file
"""
struct SourceText # TODO: Make this be a 0-based AbstractString?
    data::Vector{UInt8}
    filename::String
end

SourceText(code::Vector{UInt8}, filename) = SourceText(code, filename)
SourceText(code::AbstractString, filename) = SourceText(Vector{UInt8}(String(code)), filename)

SourceText(;     filename="none") = SourceText(read(filename), filename)
SourceText(code; filename="none") = SourceText(code, filename)

function Base.show(io::IO, file::SourceText)
    buf = IOBuffer(file.data)
    println(io, "SourceText(\"\"\"")
    for i = 1:20
        print(io, readline(buf, keep=true))
    end
    if !eof(buf)
        println(io, "…")
    end
    print(io, "\"\"\"; filename=$(repr(file.filename)))")
end

Base.getindex(file::SourceText, rng::AbstractUnitRange) = String(file.data[first(rng)+1:last(rng)])

struct IndexedSource <: AbstractVector{String}
    file::SourceText
    # offsets contains the (zero-based) byte offset for the character at the
    # start of each line. One additional offset is included past the end of the
    # file.
    offsets::Vector{UInt64}
end

function IndexedSource(file::SourceText)
    buf = IOBuffer(file.data)
    offsets = UInt[0]
    while !eof(buf)
        line = readuntil(buf, '\n', keep=true)
        push!(offsets, position(buf))
    end
    IndexedSource(file, offsets)
end

function line_start_offset(src::IndexedSource, offset, delta_lines=0)
    if length(src.offsets) == 1
        return 0
    end
    line = searchsortedlast(src.offsets, offset)
    src.offsets[clamp(line + delta_lines, 1, length(src.offsets))]
end

function line_end_offset(src::IndexedSource, offset, delta_lines=0)
    if length(src.offsets) == 1
        return 0
    end
    line = searchsortedlast(src.offsets, offset)
    off = src.offsets[clamp(line + 1 + delta_lines, 1, length(src.offsets))]
    if off > 0
        off -= 1 # remove '\n'
    end
    off
end

function source_location(src::IndexedSource, offset; prevchar=false)
    if length(src.offsets) == 1
        # Zero lines
        return (1,1)
    end
    line = searchsortedlast(src.offsets, offset)
    if line == length(src.offsets)
        line -= 1
        partial_line = src[line]
    else
        partial_line = String(src.file.data[src.offsets[line]+1:offset+1])
    end
    col = textwidth(partial_line)
    if prevchar
        if isempty(partial_line)
            line -= 1
            col = textwidth(src[line])
        else
            col -= textwidth(last(partial_line))
        end
    end
    (line,col)
end

function source_line(src::IndexedSource, offset)
    first(source_location(src, offset))
end

function Base.summary(io::IO, src::IndexedSource)
    print(io, "IndexedSource for $(repr(src.file.filename)) with $(length(src)) lines")
end

Base.size(src::IndexedSource) = (length(src.offsets)-1,)

function Base.getindex(src::IndexedSource, line::Int)
    if line == length(src.offsets)
        # Allow line-off-the-end as error may occur at EOF
        # TODO: Is there a neater way?
        return ""
    end
    i1 = src.offsets[line] + 1    # Offsets are zero-based
    i2 = src.offsets[line+1]
    return rstrip(String(src.file.data[i1:i2]), '\n')
end

