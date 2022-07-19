module ObjectOriented
export @oodef
using Reexport

include("runtime.jl")
@reexport using .RunTime

include("compile-time.jl")
@reexport using .CompileTime

end # module
