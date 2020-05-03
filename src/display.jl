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
        "Unknown error!"
    else
        "Unknown error code ($errcode)"
    end
end

# TODO: line numbers + terminal links in message!!

function print_src_lines(printfunc::Function, io::IO, src, indexed, rng)
    if first(rng) >= last(rng)
        return
    end
    text = src[rng]
    first_line = source_line(indexed, first(rng))
    textlines = split(text, '\n')
    for (i,linetext) in enumerate(textlines)
        if i > 1 || first(rng) == line_start_offset(indexed, first(rng))
            # TODO: terminal hyperlinks in line numbers!!
            #printstyled(io, lpad(first_line+i-1, 3), color=:underline)
            print(io, lpad(first_line+i-1, 3), "│")
        end
        printfunc(io, linetext)
        if i < length(textlines) || last(rng) == line_end_offset(indexed, last(rng))
            println(io)
        end
    end
end
print_src_lines(io::IO, src, indexed, rng) = print_src_lines(print, io, src, indexed, rng)

function display_diagnostic(io, src, ex0, offset0; ctxlines=3)
    trace = first_error(ex0, offset0)
    if errorof(first(trace[end])) == CSTParser.UnexpectedToken && length(trace) > 1
        ex,offset = trace[end-1]
    else
        ex,offset = trace[end]
    end
    indexed = IndexedSource(src)

    line,col = source_location(indexed, offset)
    println(io, "Parsing failed at $(src.filename):$line:$col")

    bad_off1 = offset
    bad_off2 = offset+ex.span

    toplevel_ctx = line_start_offset(indexed, offset0, 0):line_end_offset(indexed, offset0, ctxlines)

    prefix_ctx = line_start_offset(indexed, bad_off1, -ctxlines):bad_off1

    # Show toplevel context
    if source_line(indexed, last(toplevel_ctx)) + 1 < source_line(indexed, first(prefix_ctx))
        topline = source_line(indexed, first(toplevel_ctx))
        println(io, "In top-level expression at $(src.filename):$topline")
        print_src_lines(io, src, indexed, toplevel_ctx)
        println("...")
    else
        prefix_ctx = first(toplevel_ctx):last(prefix_ctx)
    end

    # Show prefix lines
    print_src_lines(io, src, indexed, prefix_ctx)

    # Format Bad lines
    bad_rng = bad_off1:bad_off2
    if first(bad_rng) == last(bad_rng)
        # Show empty char! Which char should we use here? '□' is nice but
        # probably not portable
        printstyled(io, '▄', color=:red, bold=true)
    else
        print_src_lines(io, src, indexed, bad_rng) do io,linetext
            print_underlined(io, linetext, color=:red, bold=true)
        end
    end

    # Suffix
    suffix_ctx = bad_off2:line_end_offset(indexed, bad_off2, ctxlines)
    print_src_lines(io, src, indexed, suffix_ctx)

    println(io)

    # For now, explaining errors doesn't work very well...
    printstyled(io, string(explain_error(first(trace[end])), "\n"); color=:red)
end

