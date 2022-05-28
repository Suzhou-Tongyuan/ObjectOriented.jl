module RunTime
export Object, BoundMethod, Property
export construct
export direct_fields, direct_methods, base_field, ootype_bases, getproperty_fallback, setproperty_fallback!
export get_base, check_abstract, issubclass, isinstance

## RTS functions and types

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

Base.@inline (m::BoundMethod{This, Func})(args...; kwargs...) where {This, Func} = m.func(m.this, args...; kwargs...)

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


Base.@inline function get_base(x::T, t) where T
    Base.getfield(x, base_field(T, t))
end

function base_field(T, t)
    error("type $T has no base type $t")
end

"""查询类型没有实现的抽象方法，用以检查目的。
"""
Base.@inline function check_abstract(t) Pair[] end

Base.@inline function issubclass(a :: Type, b :: Type)
    false
end

Base.@inline function isinstance(:: T, cls) where T
    issubclass(T, cls)
end

## END

_unwrap(::Type{InitField{Sym, Base}}) where {Sym, Base} = (Sym, Base)
_unwrap(x) = nothing

function _find_index(arr, x)
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
            if isbitstype(types[i]) && sizeof(types[i]) === 0
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
