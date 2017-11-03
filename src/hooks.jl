module BaseHooks

using CSTParser
using CSTParser: Diagnostics
using FancyDiagnostics: display_diagnostic
using Base: Meta

struct REPLDiagnostic
    error_code::Diagnostics.ErrorCodes
    fname::AbstractString
    text::AbstractString
    diags::Any
end

function Base.showerror(io::IO, d::REPLDiagnostic, bt)
    print_with_color(:white,io,"")
    display_diagnostic(io, d.text, d.diags; filename = d.fname)
end
Base.display_error(io::IO, d::REPLDiagnostic, bt) = Base.showerror(io, d, bt)

function Base.showerror(io::IO, d::REPLDiagnostic)
    print_with_color(:white,io,"")
    display_diagnostic(io, d.text, d.diags; filename = d.fname)
end

function _include_string(m::Module, fname, text)
    ps = CSTParser.ParseState(text)
    local result = nothing
    while !ps.done && !ps.errored
        result, ps = Parser.parse(ps)
        if ps.errored
            throw(REPLDiagnostic(fname, text, ps.diagnostics))
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
    diag.error_code in (
        Diagnostics.UnexpectedInputEnd,
        Diagnostics.UnexpectedStringEnd,
        Diagnostics.UnexpectedCommentEnd,
        Diagnostics.UnexpectedBlockEnd,
        Diagnostics.UnexpectedCmdEnd,
        Diagnostics.UnexpectedCharEnd)
end

function Base.parse(str::AbstractString, pos::Int; greedy::Bool=true, raise::Bool=true)
    # Non-greedy mode not yet supported
    @assert greedy
    io = IOBuffer(str)
    seek(io, pos-1)
    ps = CSTParser.ParseState(io)
    result, ps = CSTParser.parse(ps)
    if ps.errored
        diag = REPLDiagnostic(ps.error_code, "REPL", str, ps.diagnostics)
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

function Base.parse_input_line(code::String; filename::String="none")
    ps = CSTParser.ParseState(code)
    result, ps = CSTParser.parse(ps)
    if ps.errored
        diag = REPLDiagnostic(ps.error_code, filename, code, ps.diagnostics)
        return is_incomplete(diag) ? Expr(:incomplete, diag) : Expr(:error, diag)
    end
    result == nothing && return result
    Expr(result)
end

if ccall(:jl_generating_output, Cint, ()) == 0
    REDIRECTED_STDERR = STDERR
    redirect_stderr(ORIG_STDERR)
end

end
