using CSTParser
using CSTParser: typof, EXPR

# Find first parser error. All other errors are ignored.
function first_error(ex::EXPR)
    _first_error(ex, Tuple{EXPR,Int}[], 0)
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

function cst_parse(src::SourceFile, rule)
    buf = IOBuffer(src.data)
    ps = CSTParser.ParseState(buf)
    cont = rule == 2 ? false : true
    cst,_ = CSTParser.parse(ps, cont)
    err_trace = first_error(cst)
    if !isnothing(err_trace)
        report_error(stderr, src, err_trace)
    end
    cst
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

function explain_error(err_trace)
    ex,_ = err_trace[end]
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

function report_error(io, src, err_trace; ctxlines=3)
    indexed = IndexedSource(src)
    ex,offset = err_trace[end]
    line,col = source_location(indexed, offset)
    for ln = max(1,line-ctxlines):max(0,line-1)
        println(io, rstrip(indexed[ln]))
    end
    endline,endcol = source_location(indexed, offset + ex.span)
    endcol2 = endline == line ? endcol : textwidth(indexed[line])
    println(io, rstrip(indexed[line]))
    print(io, ' '^(col-1))
    printstyled(io, make_underline(endcol2-col+1); color=:green, bold = true)
    println(io)
    printstyled(io, "ERROR"; color=:red)
    println(io, " at $(src.filename):$line:$col")
    println(io, explain_error(err_trace))
    println(io)
    e2 = deepcopy(ex)
    e2.parent=nothing
    dump(e2)
end

# jl_parse implementation using CSTParser
function julia_jl_parse(text, text_len, filename, filename_len, pos0, rule)
    if rule == 1
        error("TODO")
    elseif rule != 2 && rule != 3
        error("Unknown parser rule: $rule")
    end
    if pos0 != 0
        error("TODO")
    end
    src = SourceFile(unsafe_wrap(Array, text, text_len),
                     filename=unsafe_string(filename, filename_len))
    cst = cst_parse(src, rule)
    ex = Expr(cst)
    if ex isa Expr && ex.head == :file
        ex = Expr(:toplevel, ex.args...)
    end
    return Core.svec(ex, text_len)
end

# Extra shim for sanity during development
function _julia_jl_parse(text, text_len, filename, filename_len, pos0, rule)
    try
        res = Base.invokelatest(julia_jl_parse, text, text_len,
                                filename, filename_len, pos0, rule)
        return res
    catch exc
        @error "Calling CSTParser failed. Falling back to flisp parser" #=
        =#     exception=exc,catch_backtrace()
        return @ccall jl_fl_parse(text::Ptr{UInt8}, sizeof(text)::Csize_t,
                                  filename::Ptr{UInt8}, sizeof(filename)::Csize_t,
                                  pos0::Csize_t, rule::Cint)::Any
    end
end

function set_parser!()
    parser = @cfunction(_julia_jl_parse, Any,
                        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Csize_t, Cint))
    @ccall jl_set_parser(parser::Ptr{Cvoid})::Cvoid
end

# Hack: quick test tool
function test_jl_parse(text, filename, pos, rule)
    pos0 = pos-1
    parser = @eval @cfunction(_julia_jl_parse, Any,
                        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Csize_t, Cint))
    @ccall $parser(text::Ptr{UInt8}, sizeof(text)::Csize_t,
                   filename::Ptr{UInt8}, sizeof(filename)::Csize_t,
                   pos0::Csize_t, rule::Cint)::Any
end

#=
using FancyDiagnostics: display_diagnostic
using Base: Meta

struct REPLDiagnostic
    fname::AbstractString
    text::AbstractString
    diags::Any
end

function Base.showerror(io::IO, d::REPLDiagnostic, bt; backtrace=false)
    printstyled(io, ""; color=:white)
    display_diagnostic(io, d.text, d.diags; filename = d.fname)
end
Base.display_error(io::IO, d::REPLDiagnostic, bt) = Base.showerror(io, d, bt)

function Base.showerror(io::IO, d::REPLDiagnostic)
    printstyled(io, ""; color=:white)
    display_diagnostic(io, d.text, d.diags; filename = d.fname)
end

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

# Pirate base definitions
# mute override warnings
if ccall(:jl_generating_output, Cint, ()) == 0
    ORIG_STDERR = STDERR
    redirect_stderr()
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

if ccall(:jl_generating_output, Cint, ()) == 0
    REDIRECTED_STDERR = STDERR
    redirect_stderr(ORIG_STDERR)
end
=#

