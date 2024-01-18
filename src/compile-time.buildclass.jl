import ObjectOriented.RunTime: Object
using DataStructures

Base.@enum PropertyKind MethodKind GetterPropertyKind SetterPropertyKind
MLStyle.is_enum(::PropertyKind) = true
MLStyle.pattern_uncall(e::PropertyKind, _, _, _, _) = MLStyle.AbstractPatterns.literal(e)

struct PropertyDefinition
    name::Symbol
    def::Any # nothing for abstract methods
    from_type::Any
    kind :: PropertyKind
end

lift_to_quot(x::PropertyDefinition) = Expr(:call, PropertyDefinition, lift_to_quot(x.name), x.def, x.from_type, x.kind)
lift_to_quot(x::Symbol) = QuoteNode(x)
lift_to_quot(x) = x
function lift_to_quot(x::Dict)
    pair_exprs = Expr[:($(lift_to_quot(k)) => $(lift_to_quot(v))) for (k, v) in x]
    :($Dict($(pair_exprs...)))
end

struct PropertyName
    is_setter :: Bool
    name :: Symbol
end

macro getter_prop(name)
    esc(:($PropertyName(false, $name)))
end

macro setter_prop(name)
    esc(:($PropertyName(true, $name)))
end

Base.show(io::IO, prop_id::PropertyName) = print(io, string(prop_id.name) * " " * (prop_id.is_setter ? "(setter)" : "(getter)"))

const sym_generic_type = Symbol("generic::Self")

Base.@inline function _union(::Type{<:Object{I}}, ::Type{<:Object{J}}) where {I, J}
    Object{Union{I, J}}
end

Base.@pure function _merge_shape_types(@nospecialize(t), @nospecialize(xs...))
    ts = Any[t]
    for x in xs
        x isa DataType || error("invalid base type $x")
        append!(ts, _shape_type(x).parameters)
    end
    Object{Union{ts...}}
end

"""map a Julia type to its **shape type**.
Given an OO type `Cls` whose orm is `[Cls, Base1, Base2]`,
the corresponding shape type is `_shape_type(Cls) == Object{Union{Cls, Base1, Base2}}`.
"""
_shape_type(x) = x

Base.@pure function like(@nospecialize(t))
    if t <: Object
        x = _shape_type(t)
        if x === t
            error("invalid base type $t: no an OO type")
        end
        if x isa DataType
            v = gensym(:t)
            vt = TypeVar(v, x.parameters[1], Any)
            UnionAll(vt, Core.apply_type(Object, vt))
        else
            ts = Any[]
            while x isa UnionAll
                push!(ts, x.var)
                x = x.body
            end
            v = gensym(:t)
            vt = TypeVar(v, x.parameters[1], Any)
            x = UnionAll(vt, Core.apply_type(Object, vt))
            while !isempty(ts)
                x = UnionAll(pop!(ts), x)
            end
            x
        end
    else
        error("$t is not an object type")
    end
end


"""`@like(type)` convert a Julia type to its covariant shape type.
Given an OO type `Cls` whose orm is `[Cls, Base1, Base2]`,
the corresponding covariant shape type is `@like(Cls) == Object{U} where U >: Union{Cls, Base1, Base2}`.
"""
macro like(t)
    esc(:($like($t)))
end

"""
define (abstract) properties such as getters and setters:
```
## Abstract
@oodef struct IXXX
    @property(field) do
        get
        set
    end
end

## Concrete
@oodef struct XXX1 <: IXXX
    @property(field) do
        get = self -> 1
        set = (self, value) -> ()
    end
end
```
"""
macro property(f, ex)
    esc(Expr(:do, :(define_property($ex)), f))
end

macro base(X)
    esc(:($ObjectOriented.RunTime.InitField{$ObjectOriented.base_field($sym_generic_type, $X), $X}()))
end

@inline function _base_initfield(generic_type, :: Type{X}) where X
    ObjectOriented.RunTime.InitField{ObjectOriented.base_field(generic_type, X), X}()
end

macro mk()
    esc(@q begin
        $__source__
        $ObjectOriented.construct(ObjectOriented.RunTime.default_initializers($sym_generic_type), $sym_generic_type)
    end)
end

function _mk_arguments!(__module__::Module, __source__::LineNumberNode, arguments::Vector{Any}, ln::LineNumberNode, arg)
    @switch arg begin
        @case ::LineNumberNode
            ln = arg
            return ln
        @case Expr(:tuple, args...)
            for arg in args
                ln = _mk_arguments!(__module__, __source__, arguments, ln, arg)
            end
            return ln
        @case Expr(:call, _...)
            sym_basecall = gensym("basecall")
            push!(arguments, Expr(
                :block,
                ln,
                :($sym_basecall = $arg),
                :($_base_initfield($sym_generic_type, typeof($sym_basecall)))
            ))
            push!(arguments, sym_basecall)
            return ln
        @case :($a = $b)
            a = __module__.macroexpand(__module__, a)
            if a isa Symbol
                a =  :($ObjectOriented.RunTime.InitField{$(QuoteNode(a)), nothing}())
            end
            push!(arguments, Expr(:block, ln, a))
            push!(arguments, Expr(:block, ln, b))
            return ln
        @case _
            error("invalid construction statement $arg")
    end
end

macro mk(ex)
    arguments = []
    ln = __source__
    @switch ex begin
        @case Expr(:block, args...)
            for arg in args
                ln = _mk_arguments!(__module__, __source__, arguments, ln, arg)
            end
        @case _
            ln = _mk_arguments!(__module__, __source__, arguments, ln, ex)
    end
    esc(@q begin
        $__source__
        # $ObjectOriented.check_abstract($sym_generic_type) # TODO: a better mechanism to warn abstract classes
        $ObjectOriented.construct(ObjectOriented.RunTime.default_initializers($sym_generic_type), $sym_generic_type, $(arguments...))
    end)
end

mutable struct CodeGenInfo
    cur_mod :: Module
    base_dict :: OrderedDict{Type, Symbol}
    fieldnames :: Vector{Symbol}
    typename :: Symbol
    class_where :: Vector
    class_ann :: Any
    methods :: Vector{PropertyDefinition}
    method_dict :: OrderedDict{PropertyName, PropertyDefinition}
    outblock :: Vector
end

function codegen(cur_line :: LineNumberNode, cur_mod::Module, type_def::TypeDef)
    base_dict = OrderedDict{Type, Symbol}()
    struct_block = []
    outer_block = []
    methods = PropertyDefinition[]

    fieldnames = Symbol[]
    typename = type_def.name
    default_inits = Expr[]

    traitname = Symbol(typename, "::", :trait)
    traithead = apply_curly(traitname, Symbol[p.name for p in type_def.typePars])
    custom_init :: Bool = false

    class_where = type_def_create_where(type_def)
    class_ann = type_def_create_ann(type_def)

    for each::FieldInfo in type_def.fields
        push!(struct_block, each.ln)
        if each.name in fieldnames
            throw(create_exception(each.ln, "duplicate field name $(each.name)"))
        end
        push!(fieldnames, each.name)

        type_expr = each.type
        if each.defaultVal isa Undefined
        else
            fname = gensym("$typename::create_default_$(each.name)")
            fun = Expr(:function, :($fname()), Expr(:block, each.ln, each.ln, each.defaultVal))
            push!(outer_block, fun)
            push!(default_inits, :($(each.name) = $fname))
        end
        push!(struct_block, :($(each.name) :: $(type_expr)))
    end

    for each::FuncInfo in type_def.methods
        if each.name === typename
            throw(create_exception(each.ln, "methods having the same name as the class is not allowed"))
        end

        if each.name === :new
            # automatically create type parameters if 'self' parameter is not annotated
            each.typePars = TypeParamInfo[type_def.typePars..., each.typePars...]
            insert!(each.body.args, 1, :($sym_generic_type = $class_ann))
            insert!(each.body.args, 1, each.ln)
            each.name = typename
            push!(struct_block, each.ln)

            # (partially) fix issue #10: parametric constructor warning
            if !isempty(type_def.typePars)
                if isempty(each.pars) && isempty(each.kwPars)
                # although it is generally difficult to analyze
                # the use of type parameters in AST level,
                # for the special case that the constructor has no parameters,
                # we can safely assume that the type parameters are not used
                else
                    push!(struct_block, to_expr(each))
                end
                each.name = class_ann
                push!(struct_block, to_expr(each))
            else
                # when there is no type parameters, we can safely use
                # this constructor as the default one.
                push!(struct_block, to_expr(each))
            end
            custom_init = true
            continue
        end

        push!(outer_block, each.ln)
        name = each.name
        meth_name = Symbol(typename, "::", "method", "::", name)
        each.name = meth_name
        if length(each.pars) >= 1 && each.pars[1].type isa Undefined
            each.pars[1].type = :($like($class_ann))
            each.typePars = TypeParamInfo[type_def.typePars..., each.typePars...]
        end
        push!(outer_block, try_pushmeta!(to_expr(each), :inline))
        push!(methods,
            PropertyDefinition(
                name,
                each.isAbstract ? missing : :($cur_mod.$meth_name),
                :($cur_mod.$typename),
                MethodKind))

    end

    for each::PropertyInfo in type_def.properties
        push!(outer_block, each.ln)
        name = each.name
        if !(each.set isa Undefined)
            prop = each.set
            if length(prop.pars) >= 1 && prop.pars[1].type isa Undefined
                prop.pars[1].type = :($like($class_ann))
                prop.typePars = TypeParamInfo[type_def.typePars..., prop.typePars...]
            end
            meth_name = Symbol(typename, "::", "setter", "::", name)
            prop.name = meth_name
            key = @setter_prop(name)
            push!(outer_block, try_pushmeta!(to_expr(prop), :inline))
            push!(methods,
                PropertyDefinition(
                    name,
                    prop.isAbstract ? missing : :($cur_mod.$meth_name),
                    :($cur_mod.$typename),
                    SetterPropertyKind))

        end

        if !(each.get isa Undefined)
            prop = each.get
            if length(prop.pars) >= 1 && prop.pars[1].type isa Undefined
                prop.pars[1].type = :($like($class_ann))
                prop.typePars = TypeParamInfo[type_def.typePars..., prop.typePars...]
            end
            meth_name = Symbol(typename, "::", "getter", "::", name)
            prop.name = meth_name
            key = @getter_prop(name)
            push!(outer_block, to_expr(prop))
            push!(methods,
                PropertyDefinition(
                    name,
                    prop.isAbstract ? missing : :($cur_mod.$meth_name),
                    :($cur_mod.$typename),
                    GetterPropertyKind))
        end
    end

    for (idx, each::TypeRepr) in enumerate(type_def.bases)
        base_name_sym = Symbol(typename, "::layout$idx::", string(each.base))
        base_dict[Base.eval(cur_mod, each.base)] = base_name_sym
        type_expr = to_expr(each)
        push!(struct_block, :($base_name_sym :: $type_expr))
        push!(outer_block,
                :(Base.@inline $ObjectOriented.base_field(::Type{$class_ann}, ::Type{$type_expr}) where {$(class_where...)} = $(QuoteNode(base_name_sym))))
    end

    if !custom_init
        push!(
            outer_block,
            let generic_type = class_ann
                @q if $(type_def.isMutable) || sizeof($typename) == 0
                    @eval function $typename()
                        $cur_line
                        $sym_generic_type = $class_ann
                        $(Expr(:macrocall, getfield(ObjectOriented, Symbol("@mk")), cur_line))
                    end
                end
            end
        )
    end

    defhead = apply_curly(typename, class_where)
    expr_default_initializers =
        isempty(default_inits) ? :(NamedTuple()) : Expr(:tuple, default_inits...)
    outer_block = [
        [
            :(struct $traithead end),
            :(Base.@__doc__ $(Expr(:struct,
                type_def.isMutable,
                :($defhead <: $_merge_shape_types($traithead, $(to_expr.(type_def.bases)...))),
                Expr(:block, struct_block...)))),
            :(Base.@__doc__ $ObjectOriented.CompileTime._shape_type(t::$Type{<:$typename}) = $supertype(t)),

        ];
        [
            :(Base.@__doc__ $ObjectOriented.RunTime.default_initializers(t::$Type{<:$typename}) = $expr_default_initializers)
        ];
        outer_block
    ]

    cgi = CodeGenInfo(
        cur_mod,
        base_dict,
        fieldnames,
        typename,
        class_where,
        class_ann,
        methods,
        OrderedDict{PropertyName, PropertyDefinition}(),
        outer_block
    )
    build_multiple_dispatch!(cur_line, cgi)
    Expr(:block, cgi.outblock...)
end
