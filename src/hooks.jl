struct CSTParseError <: Exception
    cst::EXPR
    src::SourceFile
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

# Determine whether an ErrorToken occurs in EXPR.
#
# NB: ParseState `errored` can be false while `has_error` is true. Maybe
# `errored` is set only when the parser hits an error it considers locally
# "non-recoverable" ???
function has_error(cst::EXPR)
    if typof(cst) == CSTParser.ErrorToken
        return true
    elseif isnothing(cst.args)
        return false
    else
        return any(has_error, cst.args)
    end
end

function to_Expr(cst, src, offset)
    if has_error(cst)
        # Remove cst.parent ?
        Expr(:error, CSTParseError(cst, src, offset))
    else
        Expr(cst)
    end
end

function cst_parse(src::SourceFile, offset; rule::Symbol=:statement, options...)
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
    if has_error(cst)
        # Ugh: src.data is `unsafe_wrap`d => deepcopy
        src = deepcopy(src)
    end
    srccopy = nothing
    if typof(cst) == CSTParser.FileH
        args = Any[]
        for a in cst.args
            push!(args, to_Expr(a, src, offset))
            offset += a.fullspan
        end
        ex = Expr(:toplevel, args...)
    else
        ex = to_Expr(cst, src, offset)
        offset += cst.fullspan
    end
    return ex, offset
end

function fl_parse(text, text_len, filename, filename_len, offset, rule)
    @ccall jl_fl_parse(text::Ptr{UInt8}, sizeof(text)::Csize_t,
                       filename::Ptr{UInt8}, sizeof(filename)::Csize_t,
                       offset::Csize_t, rule::Any)::Any
end

# Extra shim for sanity during development
function _julia_jl_parse(text, text_len, filename, filename_len, offset, options)
    # flisp parser uses single rule Symbol as options
    opts = options isa Symbol ? (rule=options,) : options
    try
        if opts.rule == :atom
            # TODO!
            return fl_parse(text, text_len, filename, filename_len, offset, opts.rule)
        end
        src = SourceFile(unsafe_wrap(Array, text, text_len),
                         filename=unsafe_string(filename, filename_len))
        ex, pos = cst_parse(src, offset; opts...)
        # Rewrap in an svec for use by the C code
        return Core.svec(ex, pos)
    catch exc
        @error("Calling CSTParser failed — disabling!",
               exception=(exc,catch_backtrace()),
               offset=offset,
               code=String(unsafe_wrap(Array, text, text_len))
        )
        panic!()
    end
    return fl_parse(text, text_len, filename, filename_len, offset, opts.rule)
end

function init!()
    # Debug hack - FIXME don't use @eval here!
    parser = @eval @cfunction(_julia_jl_parse, Any,
                              (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Csize_t, Any))
    @ccall jl_set_parser(parser::Ptr{Cvoid})::Cvoid
end

function panic!()
    @ccall jl_set_parser(cglobal(:jl_fl_parse)::Ptr{Cvoid})::Cvoid
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

