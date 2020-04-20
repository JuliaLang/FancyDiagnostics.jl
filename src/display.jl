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
    # FIXME: Framework for explaining parse errors
    errcode = CSTParser.errorof(ex)
    if errcode == CSTParser.UnexpectedToken
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

function display_diagnostic(io, src, ex0, offset0; ctxlines=3)
    trace = first_error(ex0, offset0)
    ex,offset = trace[end]
    indexed = IndexedSource(src)
    line,col = source_location(indexed, offset)
    println(io, "Parsing failed at $(src.filename):$line:$col")
    for ln = max(1,line-ctxlines):max(0,line-1)
        println(io, rstrip(indexed[ln]))
    end
    endline,endcol = source_location(indexed, offset + ex.span, prevchar=true)
    endcol2 = endline == line ? endcol : textwidth(indexed[line])
    println(io, rstrip(indexed[line]))
    print(io, ' '^max(0,col-1))
    printstyled(io, make_underline(endcol2-col+1); color=:green, bold = true)
    println(io)
    printstyled(io, string(explain_error(ex), "\n"); color=:red)
    println(io)
    # DEBUG: Dump node
    #e2 = deepcopy(ex)
    #e2.parent=nothing
    #dump(e2)
end

