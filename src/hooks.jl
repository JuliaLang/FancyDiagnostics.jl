struct CSTParseError <: Exception
    cst::EXPR
    src::SourceText
    index::UInt64
end

function display_diagnostic(io, err::CSTParseError)
    display_diagnostic(io, err.src, err.cst, err.index)
end

function Base.showerror(io::IO, err::CSTParseError, bt; backtrace=false)
    display_diagnostic(io, err)
end
Base.display_error(io::IO, err::CSTParseError, bt) = Base.showerror(io, err, bt)

function Base.showerror(io::IO, err::CSTParseError)
    display_diagnostic(io, err)
end

function to_Expr(cst, src, offset)
    if CSTParser.has_error(cst)
        # Remove cst.parent ?
        Expr(:error, CSTParseError(cst, src, offset+1))
    else
        CSTParser.to_Expr(CSTParser.EXPRIndexer(cst, String(copy(src.data)), src.filename))
    end
end

function cst_parse(src::SourceText, offset; rule::Symbol=:statement)
    if rule ∉ (:atom,:statement,:all)
        error("Unknown parser rule: $rule")
    end
    # Parse
    buf = IOBuffer(src.data)
    seek(buf, offset)
    ps = CSTParser.ParseState(buf)
    cst,ps = CSTParser.parse(ps, rule == :all)
    # Convert to Expr
    if typof(cst) == CSTParser.FileH
        args = Any[]
        for a in cst.args
            e = to_Expr(a, src, offset)
            push!(args, e)
            if e isa Expr && e.head == :toplevel
                break
            end
            offset += a.fullspan
        end
        ex = Expr(:toplevel, args...)
    else
        ex = to_Expr(cst, src, offset)
        offset += cst.fullspan
    end
    return ex, offset
end

# Extra shim for sanity during development
function julia_parse(text, filename, offset, options)
    if options == :atom
        # TODO!
        return Core.Compiler.fl_parse(text, filename, offset, options)
    end
    try
        if text isa Core.SimpleVector # May be passed in from C entry points
            (ptr,len) = text
            text = String(unsafe_wrap(Array, ptr, len))
        end
        src = SourceText(text, filename=filename)
        ex, pos = cst_parse(src, offset; rule=options)
        # Rewrap result in an svec for use by the C code
        return Core.svec(ex, pos)
    catch exc
        @error("Calling CSTParser failed — disabling!",
               exception=(exc,catch_backtrace()),
               offset=offset,
               code=text)
        panic!()
    end
    return Core.Compiler.fl_parse(text, filename, offset, options)
end

function enable!()
    Core.eval(Core, :(_parse = $julia_parse))
    nothing
end

function disable!()
    Core.eval(Core, :(_parse = Core.Compiler.fl_parse))
    nothing
end
