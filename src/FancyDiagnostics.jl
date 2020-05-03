module FancyDiagnostics

using CSTParser
using CSTParser: typof, EXPR, kindof, errorof

using Tokenize

include("LineNumbers.jl")
include("display.jl")
include("hooks.jl")

end # module
