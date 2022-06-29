module CompileTime
export @oodef, @mk, @base, @property
export PropertyName, like, @like

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@compiler_options"))
    @eval Base.Experimental.@compiler_options compile=min infer=no optimize=0
end

import TyOOP
using MLStyle
using MacroTools: @q
using DataStructures
include("compile-time.utils.jl")
include("compile-time.reflection.jl")
include("compile-time.c3_linearize.jl")
include("compile-time.buildclass.jl")
include("compile-time.static_dispatch.jl")

macro oodef(ex)
    preprocess(x) = Base.macroexpand(__module__, x)
    type_def = parse_class(__source__, ex, preprocess=preprocess)
    esc(canonicalize_where(codegen(__source__, __module__, type_def)))
end

end # module
