## RTS functions and types
module RunTime
using MLStyle
export Object, BoundMethod, Property
export construct, shape_type
export ootype_bases, ootype_mro
export direct_fields, direct_methods, base_field, getproperty_fallback, setproperty_fallback!
export get_base, set_base!, check_abstract, issubclass, isinstance
export getproperty_typed, setproperty_typed!

export @typed_access

"""
用来实现`@construct`宏。
该单例类型传递给generated function `construct`，
用来对任意结构体构造零开销、参数无序的构造器。

用法：
    TyOOP.construct(目标类型, InitField{field符号, nothing或基类对象}())
"""
struct InitField{Sym, Base} end
abstract type Object{U} end

struct BoundMethod{This, Func}
    this:: This
    func:: Func
end

@inline (m::BoundMethod{This, Func})(args...; kwargs...) where {This, Func} = m.func(m.this, args...; kwargs...)

@inline function getproperty_typed(x, ::Val{T}) where T
    getproperty(x, T)
end

@inline function setproperty_typed!(x, value, ::Val{T}) where T
    setproperty!(x, T, value)
end

typed_access(x) = x

function typed_access(ex::Expr)
    @match ex begin
        :($a.$(b::Symbol) = $c) => :($setproperty_typed!($(typed_access(a)), typed_access(c), $(QuoteNode(Val(b)))))
        :($a.$(b::Symbol)) => :($getproperty_typed($(typed_access(a)), $(QuoteNode(Val(b)))))
        Expr(head, args...) => Expr(head, typed_access.(args)...)
    end
end

macro typed_access(ex)
    esc(typed_access(ex))
end

function ootype_mro end
function ootype_bases(x)
    Type[]
end

function direct_methods end
function direct_fields end

function getproperty_fallback(self, name)
    error("unknown property '$name' for object '$self'")
end

function setproperty_fallback!(self, name, value)
    error("unknown property '$name' for object '$self'")
end

@inline function get_base(x::T, t) where T
    Base.getfield(x, base_field(T, t))
end

@inline function set_base!(x::T, base::BaseType) where {T, BaseType}
    Base.setfield!(x, base_field(T, BaseType), base)
end

Base.@pure function base_field(T, t)
    error("type $T has no base type $t")
end

"""查询类型没有实现的抽象方法，用以检查目的。
"""
function check_abstract end

@inline function issubclass(a :: Type, b :: Type)
    false
end

@inline function isinstance(:: T, cls) where T <: Object
    issubclass(T, cls)
end

@inline isinstance(jl_val, cls) = jl_val isa cls

## END

_unwrap(::Type{InitField{Sym, Base}}) where {Sym, Base} = (Sym, Base)
_unwrap(x) = nothing

function _find_index(@nospecialize(arr), @nospecialize(x))
    for i in 1:length(arr)
        e = arr[i]
        if e == x
            return i
        end
    end
    return -1
end

function mk_init_singleton(@nospecialize(t))
    Expr(:new, t, map(mk_init_singleton, fieldtypes(t))...)
end

@noinline function _construct(T, args)
    n = div(length(args), 2)
    names = fieldnames(T)
    types = fieldtypes(T)
    arguments = Vector{Any}(undef, length(names))
    for i = 1:n
        kw = args[2i-1]
        bare = _unwrap(kw)
        if bare === nothing
            return :(error($("unknown base type or property '$kw' for class $T")))
        end
        (sym, base) = bare
        if base === nothing
            fieldname = sym
            indice = _find_index(names, fieldname)
            if indice == -1
                return :(error($("unknown fieldname '$fieldname' for class '$T'")))
            end
            if isassigned(arguments, indice)
                return :(error($("resetting property '$fieldname' for class '$T'")))
            end
            arguments[indice] = :(args[$(2i)])
        else
            t = base
            fieldname = sym
            indice = _find_index(names, fieldname)
            if isassigned(arguments, indice)
                return :(error($("resetting base type '$t' for class '$T'")))
            end
            arguments[indice] = :(args[$(2i)])
        end
    end

    for i = eachindex(arguments)
        if !isassigned(arguments, i)
            if ismutable(T) || isbitstype(types[i]) && sizeof(types[i]) === 0
                arguments[i] = mk_init_singleton(types[i])
                continue
            end
            return :(error($("uninitialized field '$(names[i])' for class '$T'")))
        end
    end
    Expr(:new, T, arguments...)
end

@generated function construct(::Type{T}, args...) where T
    _construct(T, args)
end

end # module
