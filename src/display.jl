using .LineNumbers: SourceFile, compute_line
using CSTParser
using CSTParser.Diagnostics: Diagnostic, ErrorCodes

diag_code(D::Diagnostic{C}) where {C} = C
severity(::ErrorCodes) = "ERROR"

function display_diagnostic(io::IO, code, diagnostics::Vector{Diagnostic}; filename = "none")
    file = SourceFile(code)
    for message in diagnostics
        if isempty(message.loc)
            print_with_color(diag_code(message) isa ErrorCodes ? :red : :magenta, io, severity(diag_code(message)))
            println(io, ": ", message.message)
            continue
        end
        offset = first(message.loc)
        line = compute_line(file, offset)
        str  = String(file[line])
        lineoffset = offset - file.offsets[line] + 1
        col  = (lineoffset == 0 || isempty(str)) ? 1 :
               lineoffset > length(str) ? sum(charwidth, str) + 1 :
                sum(charwidth, str[1:lineoffset])
        if false #message.severity == :fixit
            print(io, " "^(col-1))
            print_with_color(:green, io, message.text)
            println(io)
        else
            print(io, "$filename:$line:$col " )
            print_with_color(diag_code(message) isa ErrorCodes ? :red : :magenta, io, severity(diag_code(message)), bold = true)
            println(io, ": ", message.message)
            println(io, rstrip(str))
            print(io, " "^(col-1))
            print_with_color(:green, io, string('^',"~"^(max(0,length(message.loc)-1))), bold = true)
            println(io)
        end
    end
end