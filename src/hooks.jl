struct CSTParseError <: Exception
    cst::EXPR
    src::SourceText
    offset::UInt64
end

function display_diagnostic(io, err::CSTParseError)
    display_diagnostic(io, err.src, err.cst, err.offset)
end

function Base.showerror(io::IO, err::CSTParseError, bt; backtrace=false)
    #printstyled(io, ""; color=:white) # TODO?
    display_diagnostic(io, err)
end
Base.display_error(io::IO, err::CSTParseError, bt) = Base.showerror(io, err, bt)

function Base.showerror(io::IO, err::CSTParseError)
    #printstyled(io, ""; color=:white) # TODO?
    display_diagnostic(io, err)
end

function to_Expr(cst, src, offset)
    if CSTParser.has_error(cst)
        # Remove cst.parent ?
        Expr(:error, CSTParseError(cst, src, offset))
    else
        Expr(cst)
    end
end

function cst_parse(src::SourceText, offset; rule::Symbol=:statement, options...)
    # Options other than `rule` ignored for now...
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

function init!()
    Core.Compiler.set_parser(julia_parse)
end

function panic!()
    Core.Compiler.set_parser(Core.Compiler.fl_parse)
end

#=
function _include_string(m::Module, fname, text)
    ps = CSTParser.ParseState(text)
    local result = nothing
    while !ps.done && isempty(ps.errors)
        result, ps = Parser.parse(ps)
        if !isempty(ps.errors)
            throw(REPLDiagnostic(fname, text, ps.errors))
        end
        result = ccall(:jl_toplevel_eval, Any, (Any, Any), m, Expr(result))
    end
    result
end

function Core.include(m::Module, fname::String)
    text = open(readstring, fname)
    _include_string(fname, text)
end
Base.include_string(m::Module, txt::String, fname::String) = _include_string(filename, code)

function is_incomplete(diag)
    return false
end

function Base.Meta.parse(str::AbstractString, pos::Int; greedy::Bool=true, raise::Bool=true, depwarn::Bool=true)
    # Non-greedy mode not yet supported
    @assert greedy
    io = IOBuffer(str)
    seek(io, pos-1)
    ps = CSTParser.ParseState(io)
    result, ps = CSTParser.parse(ps)
    if !isempty(ps.errors)
        diag = REPLDiagnostic("REPL", str, ps.errors)
        raise && throw(diag)
        return is_incomplete(diag) ? Expr(:incomplete, diag) : Expr(:error, diag), pos + result.fullspan
    end
    Expr(result), pos + result.fullspan
end

function Base.incomplete_tag(ex::Expr)
    Meta.isexpr(ex, :incomplete) || return :none
    (length(ex.args) != 1 || !isa(ex.args[1], REPLDiagnostic)) && return :other
    ex.args[1].error_code == Diagnostics.UnexpectedStringEnd && return :string
    ex.args[1].error_code == Diagnostics.UnexpectedCommentEnd && return :comment
    ex.args[1].error_code == Diagnostics.UnexpectedBlockEnd && return :block
    ex.args[1].error_code == Diagnostics.UnexpectedCmdEnd && return :cmd
    ex.args[1].error_code == Diagnostics.UnexpectedCharEnd && return :char
    return :other
end

function Base.parse_input_line(code::String; filename::String="none", depwarn=true)
    ps = CSTParser.ParseState(code)
    result, ps = CSTParser.parse(ps)
    if !isempty(ps.errors)
        diag = REPLDiagnostic(filename, code, ps.errors)
        return is_incomplete(diag) ? Expr(:incomplete, diag) : Expr(:error, diag)
    end
    result == nothing && return result
    Expr(result)
end

=#

