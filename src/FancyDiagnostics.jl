module FancyDiagnostics

using CSTParser
using CSTParser: typof, EXPR

include("LineNumbers.jl")
include("display.jl")
include("hooks.jl")

end # module
