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
    # use 'get_xxx' to generate a getter for 'xxx' & use 'set_xxx' to generate a setter for 'xxx'
    # for key in collect(keys(method_dict))
    #     desc :: PropertyDefinition = method_dict[key]
    #     if desc.kind === MethodKind
    #         try_remove_prefix(:set_, desc.name) do name
    #             local key = @setter_prop(name)
    #             if !haskey(method_dict, key)
    #                 method_dict[key] = PropertyDefinition(name, desc.def, desc.from_type, SetterPropertyKind)
    #             end
    #         end
    #         try_remove_prefix(:get_, desc.name) do name
    #             local key = @getter_prop(name)
    #             if !haskey(method_dict, key)
    #                 method_dict[key] = PropertyDefinition(name, desc.def, desc.from_type, GetterPropertyKind)
    #             end
    #         end
    #     end
    # end
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
end

function build_multiple_dispatch2!(ln::LineNumberNode, cgi::CodeGenInfo)
    t = cgi.typename
    out = cgi.outblock
    valid_fieldnames = cgi.fieldnames

    push!(out, ln)
    push!(out,
        :($TyOOP.direct_fields(::Type{<:$t}) = $(Expr(:tuple, QuoteNode.(valid_fieldnames)...))))

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
                @q let this = $this
                    $Base.setfield!(
                        this,
                        $(QuoteNode(sym)),
                        $convert($fieldtype(typeof(this), $(QuoteNode(sym))), value))
                end)
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


function build_val_getters(t, pairs)
    result = []
    for (k, v) in pairs
        exp = @q function $TyOOP.getproperty_typed(this::$t, ::Val{$(k)})
            return $v
        end
        push!(result, exp)
    end
    result
end

function build_val_setters(t, pairs)
    result = []
    for (k, v) in pairs
        exp = @q function $TyOOP.setproperty_typed!(this::$t, value, ::Val{$(k)})
            return $v
        end
        push!(result, exp)
    end
    result
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
    
    mro_expr = let res = :([])
        push!(res.args, :($(cgi.cur_mod).$(cgi.typename), ()))
        append!(res.args, [Expr(:tuple, k, v) for (k, v) in mro])
        res
    end

    function process_each!(
        base::Union{Expr, Type},
        path_tuple::(NTuple{N, Type} where N),
        _direct_fields::(NTuple{N, Symbol} where N),
        _direct_methods :: AbstractDict{PropertyName, PropertyDefinition}
    )
        path = Any[path_tuple...]
        push!(
            subclass_block,
            :($Base.@inline $TyOOP.issubclass(::$Type{<:$cur_mod.$t}, ::$Type{<:$base}) = true))
        for fieldname :: Symbol in _direct_fields
            if @getter_prop(fieldname) in defined
                continue
            end
            push!(defined, @getter_prop(fieldname), @setter_prop(fieldname))
            _build_field_getter_setter_for_pathed_base(push_getter!, push_setter!, :this, path, fieldname)
        end

        for (methodname :: PropertyName, desc :: PropertyDefinition) in _direct_methods
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

    # build resolution table (specifically, the bodies of getter and setter)
    process_each!(:($(cgi.cur_mod).$(cgi.typename)), (), Tuple(cgi.fieldnames), cgi.method_dict)
    for (base, path_tuple) in mro
        process_each!(base, path_tuple, TyOOP.direct_fields(base), TyOOP.direct_methods(base))
    end

    # detect all unimplemented abstract methods
    for implemented in intersect(Set{PropertyName}(keys(abstract_methods)), defined)
        delete!(abstract_methods, implemented)
    end

    check_abstract_def = @q function $TyOOP.check_abstract(::$Type{<:$t})
        $(lift_to_quot(abstract_methods))
    end

    getter_body = build_if(get_block, :($TyOOP.getproperty_fallback(this, prop)))
    setter_body = build_if(set_block, :($TyOOP.setproperty_fallback!(this, prop, value)))
    expr_propernames = Expr(:tuple, QuoteNode.(unique!(Symbol[k.name for k in defined]))...)
    out = cgi.outblock

    # codegen

    push!(out, ln)
    append!(out, subclass_block)

    ## for '@typed_access'
    append!(out, build_val_getters(t, get_block))
    append!(out, build_val_setters(t, set_block))
    

    push!(out, check_abstract_def)

    ## mro
    push!(out, :($TyOOP.ootype_mro(::$Type{<:$t}) = $mro_expr))

    ## codegen getter and setter
    push!(out, @q begin
            function $Base.getproperty(this::$cur_mod.$t, prop::$Symbol)
                $(Expr(:meta, :aggressive_constprop, :inline))
                $ln
                $getter_body
            end

            function $Base.setproperty!(this::$cur_mod.$t, prop::$Symbol, value)
                $(Expr(:meta, :aggressive_constprop, :inline))
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
