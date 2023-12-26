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
用来实现`@mk`宏。
该单例类型传递给generated function `construct`，
用来对任意结构体构造零开销、参数无序的构造器。

用法：
    ObjectOriented.construct(目标类型, InitField{field符号, nothing或基类对象}())
"""
struct InitField{Sym, Base} end
abstract type Object{U} end

"""`BoundMethod(this, func)(arg1, arg2) == func(this, arg1, arg2)`
"""
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
        :($a.$(b::Symbol) = $c) => :($setproperty_typed!($(typed_access(a)), $(typed_access(c)), $(QuoteNode(Val(b)))))
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

"""用户可自定义的默认成员访问方法。
如果为类型A定义重载此方法，则当类型A无法根据名字`name`找到成员时，该方法被调用。
"""
function getproperty_fallback(self::T, name) where T
    rself = repr(self; context = (:limit => true, :compact => true))
    error("unknown property '$name' for object '$rself' of type '$T'")
end

"""用户可自定义的默认成员赋值方法。
如果为类型A定义重载此方法，则当类型A无法根据名字`name`找到可以赋值的成员时，该方法被调用。
"""
function setproperty_fallback!(self::T, name, value) where T
    rself = repr(self; context = (:limit => true, :compact => true)e)
    error("unknown property '$name' for object '$rself' of type '$T'")
end

"""获取实例的基类实例。
```
@oodef mutable struct A
    a :: Int
    function new(a::Int)
        @mk begin
            a = 1
        end
    end
end

@oodef mutable struct B <: A
    b :: Int

    function new(a::Int, b::Int)
        @mk begin
            @base(A) = A(a)
            b = 1
        end
    end
end

b_inst = B(1, 2)
a_inst = get_base(b_inst, A) :: A
```
"""
@inline function get_base(x::T, t) where T
    Base.getfield(x, base_field(T, t))
end

@inline function set_base!(x::T, base::BaseType) where {T, BaseType}
    Base.setfield!(x, base_field(T, BaseType), base)
end

Base.@pure function base_field(T, t)
    error("type $T has no base type $t")
end

@inline _object_init_impl(self, args...; kwargs...) = nothing

@inline function object_init(self, args...; kwargs...)
    _object_init_impl(self, args...; kwargs...)
    return self
end

"""查询类型没有实现的抽象方法，用以检查目的。
用`check_abstract(Class)::Dict`查询是否存在未实现的抽象方法。
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

function default_initializers(t)
    NamedTuple()
end

@noinline function _construct(type_default_initializers, T, args)
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
            t_field = types[indice]
            arguments[indice] = :($Base.convert($t_field, args[$(2i)]))
        else
            t = base
            fieldname = sym
            indice = _find_index(names, fieldname)
            if isassigned(arguments, indice)
                return :(error($("resetting base type '$t' for class '$T'")))
            end
            t_field = types[indice]
            arguments[indice] = :($Base.convert($t_field, args[$(2i)]))
        end
    end

    default_support_symbols = type_default_initializers.parameters[1]
    for i = eachindex(arguments)
        if !isassigned(arguments, i)
            name = fieldname(T, i)
            if name in default_support_symbols
                t_field = fieldtype(T, i)
                arguments[i] = :($Base.convert($t_field, default_initializers.$name()))
                continue
            elseif ismutable(T) || isbitstype(types[i]) && sizeof(types[i]) === 0
                arguments[i] = mk_init_singleton(types[i])
                continue
            end
            return :(error($("uninitialized field '$(names[i])' for class '$T'")))
        end
    end
    Expr(:new, T, arguments...)
end

@generated function construct(default_initializers::NamedTuple, ::Type{T}, args...) where T
    _construct(default_initializers, T, args)
end

end # module
