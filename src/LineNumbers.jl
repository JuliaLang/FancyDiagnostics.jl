struct SourceFile
    data::Vector{UInt8}
    filename::String
end

SourceFile(code::Vector{UInt8}, filename) = SourceFile(code, filename)
SourceFile(code::AbstractString, filename) = SourceFile(Vector{UInt8}(String(code)), filename)

SourceFile(;     filename="none") = SourceFile(read(filename), filename)
SourceFile(code; filename="none") = SourceFile(code, filename)

function Base.show(io::IO, file::SourceFile)
    preview = readline(IOBuffer(file.data), keep=true)
    print(io, "SourceFile($(repr(string(preview, "…"))); filename=$(repr(file.filename)))")
end

struct IndexedSource <: AbstractVector{String}
    file::SourceFile
    # offsets contains the (zero-based) byte offset for the character at the
    # start of each line. One additional offset is included past the end of the
    # file.
    offsets::Vector{UInt64}
end

function IndexedSource(file::SourceFile)
    buf = IOBuffer(file.data)
    offsets = UInt64[0]
    while true
        line = readuntil(buf, '\n', keep=true)
        push!(offsets, position(buf))
        if eof(buf)
            if !endswith(line, '\n')
                offsets[end] += 1
            end
            break
        end
    end
    IndexedSource(file, offsets)
end

function source_location(src::IndexedSource, offset)
    line = searchsortedlast(src.offsets, offset)
    if line == length(src.offsets)
        offset = length(src.file.data) - 1
        line -= 1
    end
    partial_line = String(src.file.data[src.offsets[line]+1:offset+1])
    col = textwidth(partial_line)
    (line,col)
end

function Base.summary(io::IO, src::IndexedSource)
    print(io, "IndexedSource for $(repr(src.file.filename)) with $(length(src)) lines")
end

Base.size(src::IndexedSource) = (length(src.offsets)-1,)

function Base.getindex(src::IndexedSource, line::Int)
    i1 = src.offsets[line] + 1    # Offsets are zero-based
    i2 = src.offsets[line+1] - 1  # NB: skip '\n'
    return String(src.file.data[i1:i2])
end


#-------------------------------------------------------------------------------
#=
"""
Indexing adaptor to map from a flat byte offset to a `[line][offset]` pair.
Optionally, off may specify a byte offset relative to which the line number and
offset should be computed
"""
struct LineBreaking{T}
    off::UInt64
    file::SourceFile
    obj::T
end

function indtransform(lb::LineBreaking, x::Int)
    offline = compute_line(lb.file, lb.off)
    line = compute_line(lb.file, x)
    lineoffset = lb.file.offsets[line]
    off = x - lineoffset + 1
    if lineoffset < lb.off
        off -= lb.off - lineoffset
    end
    (line - offline + 1), off
end

function Base.getindex(lb::LineBreaking, x::Int)
    l, o = indtransform(lb, x)
    lb.obj[l][o]
end

function Base.setindex!(lb::LineBreaking, y, x::Int)
    l, o = indtransform(lb, x)
    lb.obj[l][o] = y
end
function Base.setindex!(lb::LineBreaking, y, x::AbstractArray)
    for i in x
        lb[i] = y
    end
end
=#

