# Find first parser error. All other errors are ignored.
function first_error(ex::EXPR, pos=0)
    _first_error(ex, Tuple{EXPR,Int}[], pos)
end

function _first_error(ex, trace, pos)
    push!(trace, (ex,pos))
    if typof(ex) === CSTParser.ErrorToken
        return trace
    end
    for i in 1:length(ex)
        res = _first_error(ex[i], trace, pos)
        if !isnothing(res)
            return res
        end
        pos += ex[i].fullspan
    end
    pop!(trace)
    return nothing
end

function print_underlined(io::IO, args...; kwargs...)
    printstyled(io, sprint(io->printstyled(io, args...; kwargs...), context=io), color=:underline)
end

print_underlined(args...; kwargs...) = print_underlined(stdout, args...; kwargs...)

function make_underline(width,
                        #chars=('^','~','^','|')
                        chars=('▔','▔','▔','▎')
                        #chars=('┗','━','┛','▎')
                       )
    if width == 0
        chars[4]
    elseif width <= 2
        chars[2]^width
    else
        string(chars[1], chars[2]^(width-2), chars[3])
    end
end

function explain_error(ex)
    errcode = errorof(ex)
    if errcode == CSTParser.UnexpectedToken
        #=
        # FIXME: how is the encoded?
        expected_kind = kindof(ex.args[1])
        expectedstr = expected_kind == Tokens.LPAREN  ? "(" :
                      expected_kind == Tokens.RPAREN  ? ")" :
                      expected_kind == Tokens.LSQUARE ? "[" :
                      expected_kind == Tokens.RSQUARE ? "]" :
                      expected_kind == Tokens.COMMA   ? "," :
                      string(expected_kind)
        "Expected $(repr(expectedstr))"
        =#
        "Unexpected token"
    elseif errcode == CSTParser.CannotJuxtapose
        "Cannot juxtapose"
    elseif errcode == CSTParser.UnexpectedWhiteSpace
        "Unexpected white space"
    elseif errcode == CSTParser.UnexpectedNewLine
        "Unexpected newline"
    elseif errcode == CSTParser.ExpectedAssignment
        "Expected assignment"
    elseif errcode == CSTParser.UnexpectedAssignmentOp
        "Unexpected assignment"
    elseif errcode == CSTParser.MissingConditional
        "Missing conditional"
    elseif errcode == CSTParser.MissingCloser
        "Missing closer"
    elseif errcode == CSTParser.InvalidIterator
        "Invalid iterator"
    elseif errcode == CSTParser.StringInterpolationWithTrailingWhitespace
        "'\$' cannot be followed by whitespace in string interpolation"
    elseif errcode == CSTParser.TooLongChar
        "Character too long"
    elseif errcode == CSTParser.Unknown
        "Parsing error"
    elseif isnothing(errcode)
        "Parsing error"
    else
        "Unknown error code ($errcode)"
    end
end

# TODO: line numbers + terminal links in message!!

function print_src_lines(printfunc::Function, io::IO, src, indexed, range)
    if isempty(range)
        return
    end
    line_ranges = intersect_lines(indexed, range)
    for (i,linerange) in enumerate(line_ranges)
        if i > 1 || first(linerange) == line_start(indexed, first(linerange))
            # TODO: terminal hyperlinks in line numbers ?
            #printstyled(io, lpad(first_line+i-1, 3), color=:underline)
            srcline = source_line(indexed, first(linerange))
            print(io, lpad(srcline, 3), "│")
        end
        printfunc(io, rstrip(src[linerange], '\n'))
        if i < length(line_ranges) || last(range) == line_end(indexed, last(range))
            println(io)
        end
    end
end
print_src_lines(io::IO, src, indexed, rng) = print_src_lines(print, io, src, indexed, rng)

function display_diagnostic(io, src, ex0, index0; ctxlines=3)
    trace = first_error(ex0, index0)
    if errorof(first(trace[end])) == CSTParser.UnexpectedToken && length(trace) > 1
        ex,index = trace[end-1]
    else
        ex,index = trace[end]
    end
    indexed = IndexedSource(src)

    line,col = source_location(indexed, index)
    println(io, "Parsing failed at $(src.filename):$line:$col")

    bad_rng = index:index+ex.span-1

    toplevel_ctx = line_start(indexed, index0, 0):line_end(indexed, index0, ctxlines)

    prefix_ctx = line_start(indexed, first(bad_rng), -ctxlines):first(bad_rng)-1

    # Show toplevel context
    if source_line(indexed, last(toplevel_ctx)) + 1 < source_line(indexed, first(prefix_ctx))
        topline = source_line(indexed, first(toplevel_ctx))
        println(io, "In top-level expression at $(src.filename):$topline")
        print_src_lines(io, src, indexed, toplevel_ctx)
        println("...")
    else
        prefix_ctx = min(first(toplevel_ctx),first(prefix_ctx)):last(prefix_ctx)
    end

    # Show prefix lines
    print_src_lines(io, src, indexed, prefix_ctx)

    # Format Bad lines
    if isempty(bad_rng)
        # Show empty char! Which char should we use here? '□' is nice but
        # probably not portable
        printstyled(io, '▄', color=:red, bold=true)
    else
        print_src_lines(io, src, indexed, bad_rng) do io,linetext
            print_underlined(io, linetext, color=:red, bold=true)
        end
    end

    # Suffix
    suffix_start = last(bad_rng)+1
    suffix_ctx = suffix_start:line_end(indexed, suffix_start, ctxlines)
    print_src_lines(io, src, indexed, suffix_ctx)

    # For now, explaining errors doesn't work very well...
    printstyled(io, explain_error(first(trace[end])); color=:red)
end

