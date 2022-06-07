import TyOOP.RunTime: Object
using DataStructures

@nospecialize

Base.@enum PropertyKind MethodKind GetterPropertyKind SetterPropertyKind
MLStyle.is_enum(::PropertyKind) = true
MLStyle.pattern_uncall(e::PropertyKind, _, _, _, _) = MLStyle.AbstractPatterns.literal(e)

struct PropertyDefinition
    name::Symbol
    def::Union{Missing, GlobalRef} # nothing for abstract methods
    from_type::GlobalRef
    kind :: PropertyKind
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

macro property(f, ex)
    esc(Expr(:do, :(define_property($ex)), f))
end

macro base(X)
    esc(:($TyOOP.RunTime.InitField{base_field($sym_generic_type, $X), $X}()))
end

macro construct()
    esc(@q begin
        $__source__
        $TyOOP.construct($sym_generic_type)
    end)
end

macro construct(ex)
    @switch ex begin
        @case Expr(:block, args...)
    end
    arguments = []
    ln = __source__
    for arg in args
        @switch arg begin
            @case ::LineNumberNode
                ln = arg
            @case :($a = $b)
                a = __module__.macroexpand(__module__, a)
                if a isa Symbol
                    a =  :($TyOOP.RunTime.InitField{$(QuoteNode(a)), nothing}())
                end
                push!(arguments, Expr(:block, ln, a))
                push!(arguments, Expr(:block, ln, b))
        end
    end
    esc(@q begin
        $__source__
        # $TyOOP.check_abstract($sym_generic_type) # TODO: a better mechanism to warn abstract classes
        $TyOOP.construct($sym_generic_type, $(arguments...))
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
    bases = OrderedDict{Type, Symbol}()
    struct_block = []
    default_parameters = []
    outer_block = []
    methods = PropertyDefinition[]

    fieldnames = Symbol[]
    typename = type_def.name

    traitname = Symbol(typename, "::", :trait)
    traithead = apply_curly(traitname, Symbol[p.name for p in type_def.typePars])

    
    class_where = type_def_create_where(type_def)
    class_ann = type_def_create_ann(type_def)

    for each::FieldInfo in type_def.fields
        push!(struct_block, each.ln)
        push!(fieldnames, each.name)

        type_expr = to_expr(each.type)
        if each.defaultVal isa Undefined
            push!(default_parameters, :($(each.name) :: $(type_expr)))
        else
            push!(default_parameters, :($(each.name) :: $(type_expr) = $(each.defaultVal)))
        end
        push!(struct_block, :($(each.name) :: $(type_expr)))
    end

    for each::FuncInfo in type_def.methods
        if each.name === typename
            throw(create_exception(each.ln, "methods having the same name as the class is not allowed"))
        end

        if each.name === :new
            each.typePars = TypeParamInfo[type_def.typePars..., each.typePars...]
            insert!(each.body.args, 1, :($sym_generic_type = $class_ann))
            insert!(each.body.args, 1, each.ln)
            each.name = typename
            push!(struct_block, each.ln)
            push!(struct_block, to_expr(each))
            each.name = class_ann
            push!(struct_block, to_expr(each))
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
        push!(outer_block, to_expr(each))
        push!(methods,
            PropertyDefinition(
                name,
                each.isAbstract ? missing : GlobalRef(cur_mod, meth_name),
                GlobalRef(cur_mod, typename),
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
            push!(outer_block, to_expr(prop))
            push!(methods,
                PropertyDefinition(
                    name,
                    prop.isAbstract ? missing : GlobalRef(cur_mod, meth_name),
                    GlobalRef(cur_mod, typename),
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
                    prop.isAbstract ? missing : GlobalRef(cur_mod, meth_name),
                    GlobalRef(cur_mod, typename),
                    GetterPropertyKind))
        end
    end

    for (idx, each::TypeRepr) in enumerate(type_def.bases)
        base_name_sym = Symbol(typename, "::layout$idx::", string(each.base))
        bases[Base.eval(cur_mod, each.base)] = base_name_sym
        type_expr = to_expr(each)
        push!(default_parameters, :($base_name_sym :: $type_expr))
        push!(struct_block, :($base_name_sym :: $type_expr))
        push!(outer_block,
                :(Base.@inline $TyOOP.base_field(::Type{$class_ann}, ::Type{$type_expr}) where {$(class_where...)} = $(QuoteNode(base_name_sym))))
    end

    defhead = apply_curly(typename, class_where)
    outer_block = [
        [
            :(struct $traithead end),
            Expr(:struct, 
                type_def.isMutable,
                :($defhead <: $_merge_shape_types($traithead, $(to_expr.(type_def.bases)...))),
                Expr(:block, struct_block...)),
            :($TyOOP.CompileTime._shape_type(t::$Type{<:$typename}) = $supertype(t)),
            
        ];
        outer_block
    ]

    cgi = CodeGenInfo(
        cur_mod,
        bases,
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
