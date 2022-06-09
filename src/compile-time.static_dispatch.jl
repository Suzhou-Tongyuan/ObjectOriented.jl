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

function build_multiple_dispatch!(
    ln::LineNumberNode,
    cgi :: CodeGenInfo)
    t = cgi.typename
    rt_methods = cgi.methods
    method_dict = cgi.method_dict
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
    cgi.method_dict = method_dict
    out = cgi.outblock
    base_dict = cgi.base_dict
    push!(out,
        :($TyOOP.ootype_bases(::$Type{<:$t}) = $(Set{Type}(keys(base_dict)))))

    for (k, v) in cgi.base_dict
        push!(out,
            :($Base.@inline $TyOOP.base_field(::$Type{<:$t}, ::Type{<:$k}) = $(QuoteNode(v))))
    end

    push!(out,
        :($TyOOP.direct_methods(::$Type{<:$t}) = $(QuoteNode(method_dict))))

    
    build_multiple_dispatch2!(ln, cgi)
    # # push!(out, :((@__MODULE__).eval($build_multiple_dispatch2(LineNumberNode(@__LINE__, Symbol(@__FILE__)), $(QuoteNode(t))))))
    # push!(out, t)
end

function build_multiple_dispatch2!(ln::LineNumberNode, cgi::CodeGenInfo)
    out = cgi.outblock
    valid_fieldnames = cgi.fieldnames
    t = cgi.typename
    
    push!(out, ln)
    push!(out,
        :($TyOOP.direct_fields(::Type{<:$t}) = $(QuoteNode(valid_fieldnames))))

    build_multiple_dispatch3!(ln, cgi)
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
    push_getter!(
        QuoteNode(sym) =>
        :($TyOOP.BoundMethod($this, $funcval)))
end

function _build_getter_property(push_getter!, this, path, sym, getter_func)
    push_getter!(
        QuoteNode(sym) =>
        :($getter_func($this)))
end

function _build_setter_property(push_setter!, this, path, sym, setter_func)
    push_setter!(
        QuoteNode(sym) =>
        :($setter_func($this, value)))
end

function build_if(pairs, else_block)
    foldr(pairs; init=else_block) do (cond, then), r
        Expr(:if, :(prop === $cond), then, r)
    end
end

function build_multiple_dispatch3!(ln::LineNumberNode, cgi::CodeGenInfo)
    t = cgi.typename
    defined = OrderedSet{PropertyName}()
    cur_mod = cgi.cur_mod
    get_block = []
    set_block = []
    abstract_methods = Dict{PropertyName, PropertyDefinition}()
    
    push_getter!(x) = push!(get_block, x)
    push_setter!(x) = push!(set_block, x)
    subclass_block = []
    
    mro = cls_linearize(collect(keys(cgi.base_dict)))
    pushfirst!(mro, (:($(cgi.cur_mod).$(cgi.typename)), ()))
    mro_expr = :[$([Expr(:tuple, k, v) for (k, v) in mro]...)]
    
    _direct_fields(base :: Expr) = cgi.fieldnames
    _direct_fields(base::Type) = TyOOP.direct_fields(base)
    _direct_methods(base :: Expr) = cgi.method_dict
    _direct_methods(base :: Type) = TyOOP.direct_methods(base)

    for (base, path_tuple) in mro
        path = Any[path_tuple...]
        push!(
            subclass_block,
            :($Base.@inline $TyOOP.issubclass(::$Type{<:$cur_mod.$t}, ::$Type{<:$base}) = true))
        for fieldname :: Symbol in _direct_fields(base)
            if @getter_prop(fieldname) in defined
                continue
            end
            push!(defined, @getter_prop(fieldname), @setter_prop(fieldname))
            _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, :this, path, fieldname)
        end

        for (methodname :: PropertyName, desc :: PropertyDefinition) in _direct_methods(base)
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

    check_abstract_def = @q function $TyOOP.check_abstract(::$Type{<:$t})
        $(QuoteNode(abstract_methods))
    end

    getter_body = build_if(get_block, :($TyOOP.getproperty_fallback(this, prop)))
    setter_body = build_if(set_block, :($TyOOP.setproperty_fallback!(this, prop, value)))
    propertynames = Symbol[k.name for k in defined]
    expr_propernames = Expr(:tuple, [QuoteNode(e) for e in unique!(propertynames)]...)
    out = cgi.outblock
    push!(out, ln)
    append!(out, subclass_block)
    push!(out, check_abstract_def)
    push!(out, :($TyOOP.ootype_mro(::$Type{<:$t}) = $mro_expr))
    push!(out, @q begin
            function $Base.getproperty(this::$cur_mod.$t, prop::$Symbol)
                $(Expr(:meta, :inline))
                $ln
                $getter_body
            end
    
            function $Base.setproperty!(this::$cur_mod.$t, prop::$Symbol, value)
                $(Expr(:meta, :inline))
                $ln
                $setter_body
            end
    
            function $Base.propertynames(::$Type{<:$cur_mod.$t})
                $(Expr(:meta, :inline))
                $ln
                $(expr_propernames)
            end
        end)
end
