import TyOOP.RunTime: Object
using DataStructures

@nospecialize

struct MethodDefinition
    name::Symbol
    def::Union{Missing, Function} # nothing for abstract methods
    from_type::Type
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

Base.@inline function _union(::Type{<:Object{Union{}}}, ::Type{<:Object{J}}) where {J}
    Object{J}
end

Base.@inline function _union(::Type{<:Object{I}}, ::Type{<:Object{Union{}}}) where {I}
    Object{I}
end


Base.@inline function _unwrap_object_unions(::Type{<:Object{I}}) where {I}
    I
end

Base.@inline function _unwrap_object_unions(::Type{<:Object{Union{}}})
    Union{}
end

Base.@inline function _like(:: Type{<:Object{I}}) where I
    Object{>:I}
end

macro like(arg, args...)
    xs = foldl(args, init = arg) do a, b
        :($_union($a, $b))
    end
    esc(:($_like($xs)))
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

            @case Expr(:do, :(prop($name)), Expr(:->, Expr(:tuple), Expr(:block, inner_body...)))
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
                    push!(vtable_block, Expr(:call, MethodDefinition, QuoteNode(Symbol(:get_, name)), getter, typename))
                end
                if setter !== nothing
                    push!(vtable_block, Expr(:call, MethodDefinition, QuoteNode(Symbol(:set_, name)), setter, typename))
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
                        Expr(:call, MethodDefinition, QuoteNode(abstract_meth_name), missing, typename))

            @case Expr(:function, expr_args, _)
                name_view = extract_funcname(stmt)
                name = name_view[]
                name_view[] = Symbol(typename, "::", name)
                push!(vtable_block,
                        Expr(:call, MethodDefinition, QuoteNode(name), stmt, typename))

            @case unrecogised
                throw(create_exception(ln, "unrecognised statement in $typename definition: $(string(stmt))"))
        end
    end

    if !custom_init
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
    tmp_var = gensym(:union_vars)
    push!(outer_block, :($tmp_var = $_unwrap_object_unions($(_unionall_expr(bases...)))))
    push!(outer_block, Expr(:struct, is_mutable, :($defhead <: $Object{$Union{$tmp_var, $traithead}}), Expr(:block, struct_block...)))
    push!(
        outer_block,
        :($__module__.eval($TyOOP.CompileTime.build_multiple_dispatch(
            LineNumberNode(@__LINE__, Symbol(@__FILE__)),
            $typename,
            rt_methods=$MethodDefinition[$(vtable_block...)],
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
    rt_methods::Vector, rt_bases::Vector)
    method_dict = Dict{Symbol, MethodDefinition}(v.name => v for v in rt_methods)
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
    visited = Set{Symbol}()
    get_block = []
    set_block = []
    abstract_methods = Dict{Symbol, MethodDefinition}()
    push_getter!(x) = push!(get_block, x)
    push_setter!(x) = push!(set_block, x)

    subclass_block = []
    for (base, path_tuple) in c3_linearized(t)
        path = Type[path_tuple...]
        push!(
            subclass_block,
            :(Base.@inline $TyOOP.issubclass(::$Type{<:$t}, ::$Type{<:$base}) = true))
        for fieldname in TyOOP.direct_fields(base)
            if fieldname in visited
                continue
            end

            push!(visited, fieldname)
            _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, :this, path, fieldname)
        end
        for (methodname, desc :: MethodDefinition) in TyOOP.direct_methods(base)
            if methodname in visited
                # override/shadowing; TODO: for vtable we need real overriding
                continue
            end
            push!(visited, methodname)

            def = desc.def
            if def === missing && !haskey(abstract_methods, methodname)
                abstract_methods[methodname] = desc
            else
                _build_method_get(push_getter!, :this, path, methodname, def)
                # handling properties
                str_methodname = string(methodname)
                if startswith(str_methodname, "get_")
                    propertyname = Symbol(SubString(str_methodname, 5))
                    _build_getter_property(push_getter!, :this, path, propertyname, def)
                elseif startswith(str_methodname, "set_")
                    propertyname = Symbol(SubString(str_methodname, 5))
                    _build_setter_property(push_setter!, :this, path, propertyname, def)
                end
            end
        end
    end

    non_concrete = [(k, abstract_methods[k]) for k in intersect(Set{Symbol}(keys(abstract_methods)), visited)]
    if !isempty(non_concrete)
        check_abstract_def = @q function $TyOOP.check_abstract(::$Type{<:$t})
            $(QuoteNode(non_concrete))
        end
    else
        check_abstract_def = nothing
    end

    _inline_meta = Expr(:meta, :inline)
    getter_body = build_if(get_block, :($TyOOP.getproperty_fallback(this, prop)))
    setter_body = build_if(set_block, :($TyOOP.setproperty_fallback!(this, prop, value)))
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
    end
end
