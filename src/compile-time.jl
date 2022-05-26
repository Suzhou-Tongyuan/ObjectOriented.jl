module CompileTime
export @oodef, @construct, @base, @like

if isdefined(Base, :Experimental)
    @eval Base.Experimental.@compiler_options compile=min infer=no optimize=0
end
import PyStyle
using MLStyle
using MacroTools: @q
using DataStructures

include("compile-time.utils.jl")
include("compile-time.class.jl")

macro oodef(ex)
    @switch ex begin
        @case :(mutable struct $defhead; $(body...) end)
              esc(canonicalize_where(oodef(__module__, __source__, true, defhead, body)))

        @case :(struct $defhead; $(body...) end)
              esc(canonicalize_where(oodef(__module__, __source__, false, defhead, body)))
    end
end

end # module
