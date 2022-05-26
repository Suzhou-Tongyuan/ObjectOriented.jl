import PyStyle.RunTime: Object

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
    esc(:($PyStyle.RunTime.InitField{base_field($sym_generic_type, $X), $X}()))
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
                    a =  :($PyStyle.RunTime.InitField{$(QuoteNode(a)), nothing}())
                end
                push!(arguments, Expr(:block, ln, a))
                push!(arguments, Expr(:block, ln, b))
        end
    end
    esc(@q begin
        $__source__
        # $PyStyle.check_abstract($sym_generic_type) # TODO: a better mechanism to warn abstract classes
        $PyStyle.construct($sym_generic_type, $(arguments...))
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

    for stmt in body
        @switch stmt begin
            @case ln::LineNumberNode

            @case :($n :: $t)
                push!(struct_block, ln)
                push!(struct_block, :($n :: $t))

            @case Expr(:function, Expr(:call, :new, args...), body)
                generic_type = apply_curly(typename, generic_params)
                insert!(body.args, 1, :($sym_generic_type = $generic_type))
                push!(struct_block, Expr(:function, :($(Expr(:call, typename, args...)) where {$(generic_params...)}), body))
            
            @case Expr(:function, abstract_meth_name::Symbol)
                push!(vtable_block, :($(QuoteNode(abstract_meth_name)), nothing))

            @case Expr(:function, expr_args, _)
                stmt = expand_macro(stmt)
                name_view = extract_funcname(stmt)
                name = name_view[]
                name_view[] = Symbol(typename, "::", name)
                push!(vtable_block, :($(QuoteNode(name)), $stmt))
        end
    end
    for base in bases
        base_name = extract_tbase(base)[1]
        base_name_sym = gensym(base_name)
        push!(base_block, Expr(:tuple, base_name, QuoteNode(base_name_sym)))
        push!(struct_block, :($base_name_sym :: $base))
    end
    

    push!(outer_block, :(struct $traithead end))
    tmp_var = gensym(:union_vars)
    push!(outer_block, :($tmp_var = $_unwrap_object_unions($(_unionall_expr(bases...)))))
    push!(outer_block, Expr(:struct, is_mutable, :($defhead <: $Object{$Union{$tmp_var, $traithead}}), Expr(:block, struct_block...)))
    push!(
        outer_block,
        :($__module__.eval($PyStyle.CompileTime.build_vtable(
            LineNumberNode(@__LINE__, Symbol(@__FILE__)),
            $typename,
            rt_methods=[$(vtable_block...)],
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
        bases = PyStyle.ootype_bases(cls)
        if isempty(bases)
            continue
        end
        for base in bases
            enqueue!(queue, (base, (path..., base)))
        end
    end
    mro
end

function build_vtable(
    ln::LineNumberNode,
    t;
    rt_methods::Vector, rt_bases::Vector)
    method_dict = Dict(rt_methods)
    base_dict = Dict(rt_bases)
    out = []
    push!(out,
        :($PyStyle.ootype_bases(::$Type{<:$t}) = $(Set{Type}(keys(base_dict)))))

    for (k, v) in base_dict
        push!(out,
            :(Base.@inline $PyStyle.base_field(::$Type{<:$t}, ::Type{<:$k}) = $(QuoteNode(v))))
    end
    
    push!(out,
        :($PyStyle.direct_methods(::$Type{<:$t}) = $(QuoteNode(method_dict))))

    push!(out, :((@__MODULE__).eval($build_vtable2(LineNumberNode(@__LINE__, Symbol(@__FILE__)), $(QuoteNode(t)), $(QuoteNode(method_dict)), $(QuoteNode(base_dict))))))
    Expr(:block, out...)
end

function build_vtable2(ln::LineNumberNode, t, method_dict, base_dict)
    names = fieldnames(t)
    base_dict_rev = Dict(v => k for (k, v) in base_dict)
    valid_fieldnames = Symbol[name for name in names if !haskey(base_dict_rev, name)]
    out = []
    push!(out,
        :($PyStyle.direct_fields(::$Type{<:$t}) = $(QuoteNode(valid_fieldnames))))

    push!(out, :((@__MODULE__).eval($build_vtable3(LineNumberNode(@__LINE__, Symbol(@__FILE__)), $(QuoteNode(t))))))
    Expr(:block, out...)
end


function _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, this, path, sym)
    if path === ()
        push_getter!(
            QuoteNode(sym) =>
            :($getfield($this, $(QuoteNode(sym)))))
        push_setter!(
            QuoteNode(sym) =>
            :($setfield!($this, $(QuoteNode(sym)), value)))
    else
        (head, path) = (path[1], path[2:end])
        _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, :($PyStyle.get_base($this, $head)), path, sym)
    end
end

function _build_method_get(push_getter!, this, path, sym, funcval)
    if path === ()
        push_getter!(
            QuoteNode(sym) =>
            :($PyStyle.BoundMethod($this, $funcval)))
    else
        (head, path) = (path[1], path[2:end])
        _build_method_get(push_getter!, :($PyStyle.get_base($this, $head)), path, sym, funcval)
    end
end

function build_if(pairs, else_block)
    foldr(pairs; init=else_block) do (cond, then), r
        Expr(:if, :(prop === $cond), then, r)
    end
end

function build_vtable3(ln, t)
    visited = Set{Symbol}()
    get_block = []
    set_block = []
    abstract_methods = Dict{Symbol, Any}()
    push_getter!(x) = push!(get_block, x)
    push_setter!(x) = push!(set_block, x)
    
    subclass_block = []
    for (base, path) in c3_linearized(t)
        push!(
            subclass_block,
            :(Base.@inline $PyStyle.issubclass(::$Type{<:$t}, ::$Type{<:$base}) = true))
        for fieldname in PyStyle.direct_fields(base)
            if fieldname in visited
                continue
            end
            
            push!(visited, fieldname)
            _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, :this, path, fieldname)
        end
        for (methodname, def) in PyStyle.direct_methods(base)
            if methodname in visited
                continue
            end
            
            push!(visited, methodname)
            
            if def === nothing && !haskey(abstract_methods, methodname)
                abstract_methods[methodname] = base
            else
                _build_method_get(push_getter!, :this, path, methodname, def)
            end
        end
    end

    non_concrete = [(k, abstract_methods[k]) for k in intersect(Set{Symbol}(keys(abstract_methods)), visited)]
    if !isempty(non_concrete)
        check_abstract_def = @q function $PyStyle.check_abstract(::$Type{<:$t})
            $(QuoteNode(non_concrete))
        end
    else
        check_abstract_def = nothing
    end

    _inline_meta = Expr(:meta, :inline)
    getter_body = build_if(get_block, :($PyStyle.getproperty_fallback(this, prop)))
    setter_body = build_if(set_block, :($PyStyle.setproperty_fallback!(this, prop, value)))
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



