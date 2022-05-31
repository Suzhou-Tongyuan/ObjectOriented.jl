import TyOOP.RunTime: Object
using DataStructures
export PropertyName, like, @like, @property

@nospecialize

Base.@enum PropertyKind MethodKind GetterPropertyKind SetterPropertyKind
MLStyle.is_enum(::PropertyKind) = true
MLStyle.pattern_uncall(e::PropertyKind, _, _, _, _) = MLStyle.AbstractPatterns.literal(e)

struct PropertyDefinition
    name::Symbol
    def::Union{Missing, Function} # nothing for abstract methods
    from_type::Type
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

function _is_abstract(def::PropertyDefinition)
    def.def === missing
end

function try_remove_prefix(f, prefix::Symbol, name::Symbol)
    prefix_s = string(prefix)
    name_s = string(name)
    if startswith(name_s, prefix_s)
        return f(Symbol(SubString(name_s, ncodeunits(prefix_s) + 1)))
    end
end

split_path(x) = (x, )

function split_path(x::Expr)
    @match x begin
        :($a.$b) => (split_path(a)..., b)
    end
end


const sym_generic_type = Symbol("generic::T")

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

_shape_type(x) = x

Base.@pure function like(@nospecialize(t))
    if t <: Object
        x = _shape_type(t)
        if x === t
            error("invalid base type $t")
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

macro like(t)
    esc(:($like($t)))
end

macro property(f, ex)
    esc(Expr(:do, :(define_property($ex)), f))
end

function _unionall_expr()
    :($Union{})
end

function _unionall_expr(arg)
    arg
end

function _unionall_expr(arg, args...)
    foldl(args, init = arg) do a, b
        :($_union($a, $b))
    end
end

macro _unionall(arg, args...)
    xs = _unionall_expr(arg, args...)
    esc(xs)
end

macro base(X)
    esc(:($TyOOP.RunTime.InitField{base_field($sym_generic_type, $X), $X}()))
end

macro construct()
    esc(@q begin
        $__source__
        # $TyOOP.check_abstract($sym_generic_type) # TODO: a better mechanism to warn abstract classes
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

function oodef(__module__::Module, __source__::LineNumberNode, is_mutable::Bool, defhead::Any, body::AbstractVector)
    expand_macro(ex) = __module__.macroexpand(__module__, ex)
    defhead = expand_macro(defhead)
    defhead, bases = extract_inheritance(defhead)
    typename, generic_params_con = extract_tbase(defhead)
    generic_params = Symbol[extract_tvar(e) for e in generic_params_con]
    type_trait = Symbol(typename, "::", :trait)
    traithead = apply_curly(type_trait, generic_params)
    has_any_field = false :: Bool

    ln :: LineNumberNode = __source__
    struct_block = []
    vtable_block = []
    base_block = []
    outer_block = []
    custom_init = false
    for stmt in body
        stmt = expand_macro(stmt)
        @switch stmt begin
            @case ln::LineNumberNode

            @case :($n :: $t)
                push!(struct_block, ln)
                push!(struct_block, :($n :: $t))
                has_any_field = true

            @case Expr(:do, :(define_property($name)), Expr(:->, Expr(:tuple), Expr(:block, inner_body...)))
                setter = nothing
                getter = nothing
                for decl in inner_body
                    @switch decl begin
                        @case ln::LineNumberNode
                        @case :set
                            setter = missing
                        @case :get
                            getter = missing
                        @case :(set = $f)
                            if setter === nothing
                                setter = f
                            else
                                throw(create_exception(ln, "multiple setters for property $name"))
                            end
                        @case :(get = $f)
                            if getter === nothing
                                getter = f
                            else
                                throw(create_exception(ln, "multiple getters for property $name"))
                            end
                        @case _
                            throw(create_exception(ln, "invalid property declaration: $(string(decl))"))
                    end
                end
                if getter !== nothing
                    push!(vtable_block, Expr(:call, PropertyDefinition, QuoteNode(name), getter, typename, GetterPropertyKind))
                end
                if setter !== nothing
                    push!(vtable_block, Expr(:call, PropertyDefinition, QuoteNode(name), setter, typename, SetterPropertyKind))
                end

            @case Expr(:function, Expr(:call, &typename, args...), _)
                throw(create_exception(ln, "methods having the same name as the class is not allowed"))

            @case Expr(:function, Expr(:call, :new, args...), func_body)
                custom_init = true
                generic_type = apply_curly(typename, generic_params)
                insert!(func_body.args, 1, :($sym_generic_type = $generic_type))
                insert!(func_body.args, 1, ln)
                push!(struct_block, Expr(:function, :($(Expr(:call, typename, args...)) where {$(generic_params...)}), func_body))

            @case Expr(:function, abstract_meth_name::Symbol)
                push!(vtable_block,
                        Expr(:call, PropertyDefinition, QuoteNode(abstract_meth_name), missing, typename, MethodKind))

            @case Expr(:function, expr_args, _)
                name_view = extract_funcname(stmt)
                name = name_view[]
                name_view[] = Symbol(typename, "::", name)
                push!(vtable_block,
                        Expr(:call, PropertyDefinition, QuoteNode(name), stmt, typename, MethodKind))

            @case unrecogised
                throw(create_exception(ln, "unrecognised statement in $typename definition: $(string(stmt))"))
        end
    end

    if !custom_init && (is_mutable || !has_any_field)
        generic_type = apply_curly(typename, generic_params)
        func_body = @q begin
            $sym_generic_type = $generic_type
            $(Expr(:macrocall, getfield(TyOOP, Symbol("@construct")), __source__))
        end
        push!(struct_block, Expr(:function, :($(Expr(:call, generic_type)) where {$(generic_params...)}), func_body))
    end

    for idx in eachindex(bases)
        base = bases[idx]
        base_name = extract_tbase(base)[1]
        base_name_sym = Symbol(typename, "::layout$idx::",  base_name)
        push!(base_block, Expr(:tuple, base_name, QuoteNode(base_name_sym)))
        push!(struct_block, :($base_name_sym :: $base))
    end

    push!(outer_block, :(struct $traithead end))
    push!(outer_block, Expr(:struct, is_mutable, :($defhead <: $_merge_shape_types($traithead, $(bases...))), Expr(:block, struct_block...)))
    push!(outer_block, :($TyOOP.CompileTime._shape_type(t::$Type{<:$typename}) = $supertype(t)))
    push!(
        outer_block,
        :($__module__.eval($TyOOP.CompileTime.build_multiple_dispatch(
            LineNumberNode(@__LINE__, Symbol(@__FILE__)),
            $typename,
            rt_methods=$PropertyDefinition[$(vtable_block...)],
            rt_bases=[$(base_block...)]))))
    Expr(:block, outer_block...)
end

function c3_linearized(::Type{root}) where root
    mro = Tuple{Type, Tuple}[]
    visited = Set{Type}()
    queue = Queue{Tuple{Type, Tuple}}()
    enqueue!(queue, (root, ()))
    while length(queue) > 0
        (cls, path) = dequeue!(queue)
        # TODO: support sealed class?
        if cls in visited
            continue
        end
        push!(visited, cls)
        push!(mro, (cls, path))
        bases = TyOOP.ootype_bases(cls)
        if isempty(bases)
            continue
        end
        for base in bases
            enqueue!(queue, (base, (path..., base)))
        end
    end
    mro
end

function build_multiple_dispatch(
    ln::LineNumberNode,
    t;
    rt_methods::Vector{PropertyDefinition}, rt_bases::Vector)
    method_dict = OrderedDict{PropertyName, PropertyDefinition}()
    for proper_def in rt_methods
        name :: PropertyName =
            if proper_def.kind === SetterPropertyKind
                @setter_prop(proper_def.name)
            else
                @getter_prop(proper_def.name)
            end
        if haskey(method_dict, name)
            continue
        end
        method_dict[name] = proper_def
    end
    for key in collect(keys(method_dict))
        desc :: PropertyDefinition = method_dict[key]
        if desc.kind === MethodKind
            try_remove_prefix(:set_, desc.name) do name
                local key = @setter_prop(name)
                if !haskey(method_dict, key)
                    method_dict[key] = PropertyDefinition(name, desc.def, desc.from_type, SetterPropertyKind)
                end
            end
            try_remove_prefix(:get_, desc.name) do name
                local key = @getter_prop(name)
                if !haskey(method_dict, key)
                    method_dict[key] = PropertyDefinition(name, desc.def, desc.from_type, GetterPropertyKind)
                end
            end
        end
    end
    base_dict = Dict(rt_bases)
    out = []
    push!(out,
        :($TyOOP.ootype_bases(::$Type{<:$t}) = $(Set{Type}(keys(base_dict)))))

    for (k, v) in base_dict
        push!(out,
            :(Base.@inline $TyOOP.base_field(::$Type{<:$t}, ::Type{<:$k}) = $(QuoteNode(v))))
    end

    push!(out,
        :($TyOOP.direct_methods(::$Type{<:$t}) = $(QuoteNode(method_dict))))

    push!(out, :((@__MODULE__).eval($build_multiple_dispatch2(LineNumberNode(@__LINE__, Symbol(@__FILE__)), $(QuoteNode(t))))))
    Expr(:block, out...)
end

function build_multiple_dispatch2(ln::LineNumberNode, t)
    valid_fieldnames = Symbol[fieldnames(t)...]
    out = []
    push!(out, ln)
    push!(out,
        :($TyOOP.direct_fields(::$Type{<:$t}) = $(QuoteNode(valid_fieldnames))))

    push!(out, :((@__MODULE__).eval($build_multiple_dispatch3(LineNumberNode(@__LINE__, Symbol(@__FILE__)), $(QuoteNode(t))))))
    Expr(:block, out...)
end

function _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, this, path, sym)
    @switch path begin
        @case []
            push_getter!(
                QuoteNode(sym) =>
                :($Base.getfield($this, $(QuoteNode(sym)))))
            push_setter!(
                QuoteNode(sym) =>
                :($Base.setfield!($this, $(QuoteNode(sym)), value)))
        @case [head, path...]
            _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, :($TyOOP.get_base($this, $head)), path, sym)
    end
end

function _build_method_get(push_getter!, this, path, sym, funcval)
    @switch path begin
        @case []
            push_getter!(
                QuoteNode(sym) =>
                :($TyOOP.BoundMethod($this, $funcval)))

        @case [head, path...]
            _build_method_get(push_getter!, :($TyOOP.get_base($this, $head)), path, sym, funcval)
    end
end

function _build_getter_property(push_getter!, this, path, sym, getter_func)
    @switch path begin
        @case []
            push_getter!(
                QuoteNode(sym) =>
                :($getter_func($this)))
        @case [head, path...]
            _build_getter_property(push_getter!, :($TyOOP.get_base($this, $head)), path, sym, getter_func)
    end
end

function _build_setter_property(push_setter!, this, path, sym, setter_func)
    @switch path begin
        @case []
            push_setter!(
                QuoteNode(sym) =>
                :($setter_func($this, value)))
        @case [head, path...]
            _build_setter_property(push_setter!, :($TyOOP.get_base($this, $head)), path, sym, setter_func)
    end
end


function build_if(pairs, else_block)
    foldr(pairs; init=else_block) do (cond, then), r
        Expr(:if, :(prop === $cond), then, r)
    end
end


function build_multiple_dispatch3(ln, t)
    defined = OrderedSet{PropertyName}()
    get_block = []
    set_block = []
    abstract_methods = Dict{PropertyName, PropertyDefinition}()
    push_getter!(x) = push!(get_block, x)
    push_setter!(x) = push!(set_block, x)

    subclass_block = []
    for (base, path_tuple) in c3_linearized(t)
        path = Type[path_tuple...]
        push!(
            subclass_block,
            :(Base.@inline $TyOOP.issubclass(::$Type{<:$t}, ::$Type{<:$base}) = true))
        for fieldname :: Symbol in TyOOP.direct_fields(base)
            if @getter_prop(fieldname) in defined
                continue
            end
            push!(defined, @getter_prop(fieldname), @setter_prop(fieldname))
            _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, :this, path, fieldname)
        end

        for (methodname :: PropertyName, desc :: PropertyDefinition) in TyOOP.direct_methods(base)
            def = desc.def
            @switch (desc.kind, _is_abstract(desc)) begin
                @case (MethodKind, true)
                    haskey(abstract_methods, methodname) && continue
                    abstract_methods[methodname] = desc
                @case (MethodKind, false)
                    methodname in defined && continue
                    push!(defined, methodname)
                    _build_method_get(push_getter!, :this, path, methodname.name, def)
                @case (GetterPropertyKind, true)
                    haskey(abstract_methods, methodname) && continue
                    abstract_methods[methodname] = desc
                @case (GetterPropertyKind, false)
                    methodname in defined && continue
                    push!(defined, methodname)
                    _build_getter_property(push_getter!, :this, path, methodname.name, def)
                @case (SetterPropertyKind, true)
                    haskey(abstract_methods, methodname) && continue
                    abstract_methods[methodname] = desc
                @case (SetterPropertyKind, false)
                    methodname in defined && continue
                    push!(defined, methodname)
                    _build_setter_property(push_setter!, :this, path, methodname.name, def)
            end
        end
    end

    for implemented in intersect(Set{PropertyName}(keys(abstract_methods)), defined)
        delete!(abstract_methods, implemented)
    end

    if !isempty(abstract_methods)
        check_abstract_def = @q function $TyOOP.check_abstract(::$Type{<:$t})
            $(QuoteNode(abstract_methods))
        end
    else
        check_abstract_def = nothing
    end

    _inline_meta = Expr(:meta, :inline)
    getter_body = build_if(get_block, :($TyOOP.getproperty_fallback(this, prop)))
    setter_body = build_if(set_block, :($TyOOP.setproperty_fallback!(this, prop, value)))
    propertynames = Symbol[k.name for k in defined]
    expr_propernames = Expr(:tuple, [QuoteNode(e) for e in unique!(propertynames)]...)
    @q begin
        $ln
        $(subclass_block...)
        $check_abstract_def

        function $Base.getproperty(this::$t, prop::Symbol)
            $_inline_meta
            $ln
            $getter_body
        end

        function $Base.setproperty!(this::$t, prop::Symbol, value)
            $_inline_meta
            $ln
            $setter_body
        end

        Base.@inline function $Base.propertynames(::Type{<:$t})
            $ln
            $(expr_propernames)
        end
    end
end
