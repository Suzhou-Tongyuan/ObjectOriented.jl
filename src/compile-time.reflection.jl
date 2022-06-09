using MLStyle
struct Undefined end
const NullSymbol = Union{Symbol, Undefined}
const _undefined = Undefined()
const PVec{T, N} = NTuple{N, T}
const _pseudo_line = LineNumberNode(1)

Base.@kwdef struct TypeRepr
    base :: Any = _undefined
    typePars :: PVec{TypeRepr} = ()
end

to_expr(t::TypeRepr) =
    if isempty(t.typePars)
        t.base
    else
        :($(t.base){$(to_expr.(t.typePars)...)})
    end

Base.@kwdef mutable struct ParamInfo
    name :: Any = _undefined
    type :: Any = _undefined
    defaultVal :: Any = _undefined
    meta :: Vector{Any} = []
    isVariadic :: Bool = false
end

function to_expr(p::ParamInfo)
    res = if p.name isa Undefined
        @assert !(p.type isa Undefined)
        :(::$(p.type))
    else
        if p.type isa Undefined
            p.name
        else
            :($(p.name)::$(p.type))
        end
    end
    if p.isVariadic
        res = Expr(:..., res)
    end
    if !(p.defaultVal isa Undefined)
        res = Expr(:kw, res, p.defaultVal)
    end
    if !isempty(p.meta)
        res = Expr(:meta, p.meta..., res)
    end
    return res
end

Base.@kwdef struct TypeParamInfo
    name :: Symbol
    lb :: Union{TypeRepr, Undefined} = _undefined
    ub :: Union{TypeRepr, Undefined} = _undefined
end

function to_expr(tp::TypeParamInfo)
    if tp.lb isa Undefined
        if tp.ub isa Undefined
            tp.name
        else
            :($(tp.name) <: $(tp.ub))
        end
    else
        if tp.ub isa Undefined
            :($(tp.name) >: $(tp.lb))
        else
            :($(tp.lb) <: $(tp.name) <: $(tp.ub))
        end
    end
end

Base.@kwdef mutable struct FuncInfo
    ln :: LineNumberNode = _pseudo_line
    name :: Any = _undefined
    pars :: Vector{ParamInfo} = ParamInfo[]
    kwPars :: Vector{ParamInfo} = ParamInfo[]
    typePars :: Vector{TypeParamInfo} = TypeParamInfo[]
    returnType :: Any = _undefined # can be _undefined
    body :: Any = _undefined # can be _undefined
    isAbstract :: Bool = false
end

function to_expr(f::FuncInfo)
    if f.isAbstract
        return :nothing
    else
        args = []
        if !isempty(f.kwPars)
            kwargs = Expr(:parameters)
            push!(args, kwargs)
            for each in f.kwPars
                push!(kwargs.args, to_expr(each))
            end
        end
        for each in f.pars
            push!(args, to_expr(each))
        end
        header = if f.name isa Undefined
           Expr(:tuple, args...) 
        else
            Expr(:call, f.name, args...) 
        end
        if !(f.returnType isa Undefined)
            header = :($header :: $(f.returnType))
        end
        if !isempty(f.typePars)
            header = :($header where {$(to_expr.(f.typePars)...)})
        end
        return Expr(:function, header, f.body)
    end
end

Base.@kwdef struct FieldInfo
    ln :: LineNumberNode
    name :: Symbol
    type :: TypeRepr = TypeRepr(base=:Any)
    defaultVal :: Any = _undefined
end

Base.@kwdef struct PropertyInfo
    ln :: LineNumberNode
    name :: Symbol
    get :: Union{Undefined, FuncInfo} = _undefined
    set :: Union{Undefined, FuncInfo} = _undefined
end

Base.@kwdef mutable struct TypeDef
    ln :: LineNumberNode = _pseudo_line
    name :: Symbol = :_
    typePars :: Vector{TypeParamInfo} = TypeParamInfo[]
    bases :: Vector{TypeRepr} = TypeRepr[]
    fields :: Vector{FieldInfo} = FieldInfo[]
    properties :: Vector{PropertyInfo} = PropertyInfo[]
    methods :: Vector{FuncInfo} = FuncInfo[]
    isMutable :: Bool = false
end

function type_def_create_ann(t::TypeDef)
    if isempty(t.typePars)
        t.name
    else
        :($(t.name){$([p.name for p in t.typePars]...)})
    end
end

function type_def_create_where(t::TypeDef)
    res = []
    for each in t.typePars
        if each.lb isa Undefined
            if each.ub isa Undefined
                push!(res, each.name)
            else
                push!(res, :($(each.name) <: $(each.ub)))
            end
        else
            if each.ub isa Undefined
                push!(res, :($(each.name) >: $(each.lb)))
            else
                push!(res, :($(each.lb) <: $(each.name) <: $(each.ub)))
            end
        end
    end
    res
end

function parse_class(ln::LineNumberNode, def; preprocess::T=nothing) where T
    @switch def begin
        @case :(mutable struct $defhead; $(body...) end)
            type_def = TypeDef()
            type_def.ln = ln
            type_def.isMutable = true
            parse_class_header!(ln, type_def, defhead, preprocess = preprocess)
            parse_class_body!(ln, type_def, body, preprocess = preprocess)
            return type_def

        @case :(struct $defhead; $(body...) end)
            type_def = TypeDef()
            type_def.ln = ln
            type_def.isMutable = false
            parse_class_header!(ln, type_def, defhead, preprocess = preprocess)
            parse_class_body!(ln, type_def, body, preprocess = preprocess)
            return type_def

        @case _
            throw(create_exception(ln, "invalid type definition: $(string(def))"))
    end
end


function parse_type_repr(ln::LineNumberNode, repr)
    @switch repr begin
        @case :($typename{$(generic_params...)}) && if typename isa Symbol end
            return TypeRepr(typename, Tuple(parse_type_repr(ln, x) for x in generic_params))
        @case typename::Symbol
            return TypeRepr(typename, ())
        @case _
            throw(create_exception(ln, "invalid type representation: $repr"))
    end
end

function parse_class_header!(ln::LineNumberNode, type_def::TypeDef, defhead; preprocess::T=nothing) where T
    if preprocess !== nothing
        defhead = preprocess(defhead)
    end
    @switch defhead begin
        @case :($defhead <: {$(t_bases...)})
            for x in t_bases
                push!(type_def.bases, parse_type_repr(ln, x))
            end
        @case :($defhead <: $t_base)
            push!(type_def.bases, parse_type_repr(ln, t_base))
        @case _
    end

    local typename
    @switch defhead begin
        @case :($typename{$(generic_params...)})
            for p in generic_params
                push!(type_def.typePars, parse_type_parameter(ln, p))
            end
        @case typename
    end
    if typename isa Symbol
        type_def.name = typename
    else
        throw(create_exception(ln, "typename is invalid: $typename"))
    end
end

function parse_class_body!(ln::LineNumberNode, self::TypeDef, body; preprocess::T=nothing) where T
    for x in body
        if preprocess !== nothing
            x = preprocess(x)
        end

        if x isa LineNumberNode
            ln = x
            continue
        end

        if (field_info = parse_field_def(ln, x, fallback = nothing)) isa FieldInfo
            push!(self.fields, field_info)
            continue
        end

        if (prop_info = parse_property_def(ln, x, fallback = nothing)) isa PropertyInfo
            push!(self.properties, prop_info)
            continue
        end


        if (func_info = parse_function(ln, x, fallback = nothing, allow_lambda = false, allow_short_func = false)) isa FuncInfo
            push!(self.methods, func_info)
            continue
        end
        throw(create_exception(ln, "unrecognised statement in $(self.name) definition: $(x)"))
        
    end
end

function parse_field_def(ln :: LineNumberNode, f; fallback :: T = _undefined) where T
    @match f begin
        :($n :: $t) => FieldInfo(ln = ln, name = n, type = parse_type_repr(ln, t))
        :($n :: $t = $v) => FieldInfo(ln = ln, name = n, type = parse_type_repr(ln, t), defaultVal = v)
        :($n = $v) => FieldInfo(ln = ln, name = n, defaultVal = v)
        n :: Symbol => FieldInfo(ln = ln, name = n)
        _ =>
            if fallback isa Undefined
                throw(create_exception(ln, "invalid field declaration: $(string(f))"))
            else
                fallback
            end
    end
end

function parse_property_def(ln::LineNumberNode, p; fallback :: T = _undefined) where T
    @when Expr(:do, :(define_property($name)), Expr(:->, Expr(:tuple), Expr(:block, inner_body...))) = p begin
        name isa Symbol || throw(create_exception(ln, "invalid property name: $name"))
        setter :: Union{Undefined, FuncInfo} = _undefined
        getter :: Union{Undefined, FuncInfo} = _undefined

        for decl in inner_body
            @switch decl begin
                @case ln::LineNumberNode
                @case :set
                    setter = FuncInfo(ln = ln, isAbstract=true)
                @case :get
                    getter = FuncInfo(ln = ln, isAbstract=true)
                @case :(set = $f)
                    if setter isa Undefined
                        setter = parse_function(ln, f, allow_lambda = true, allow_short_func = false)
                    else
                        throw(create_exception(ln, "multiple setters for property $name"))
                    end
                @case :(get = $f)
                    if getter isa Undefined
                        getter = parse_function(ln, f, allow_lambda = true, allow_short_func = false)
                    else
                        throw(create_exception(ln, "multiple getters for property $name"))
                    end
                @case _
                    throw(create_exception(ln, "invalid property declaration: $(string(decl))"))
            end
        end
        return PropertyInfo(ln = ln, name = name, get = getter, set = setter)
    @otherwise
        if fallback isa Undefined
            throw(create_exception(ln, "invalid property declaration: $(string(p))"))
        else
            return fallback
        end
    end
end

function parse_parameter(ln :: LineNumberNode, p; support_tuple_parameters=true)
    self = ParamInfo()
    parse_parameter!(ln, self, p, support_tuple_parameters)
    return self
end

function parse_parameter!(ln :: LineNumberNode, self::ParamInfo, p, support_tuple_parameters)
    @switch p begin
        @case Expr(:meta, x, p)
            push!(self.meta, x)
            parse_parameter!(ln, self, p, support_tuple_parameters)
        @case Expr(:..., p)
            self.isVariadic = true
            parse_parameter!(ln, self, p, support_tuple_parameters)
        @case Expr(:kw, p, b)
            self.defaultVal = b
            parse_parameter!(ln, self, p, support_tuple_parameters)
        @case :($p :: $t)
            self.type = t
            parse_parameter!(ln, self, p, support_tuple_parameters)
        @case p::Symbol
            self.name = p
            nothing
        @case Expr(:tuple, _...)
            if support_tuple_parameters
                self.name = p
            else
                throw(create_exception(ln, "tuple parameters are not supported"))
            end
            nothing
        @case _
            throw(create_exception(ln, "invalid parameter $p"))
    end
end

function parse_type_parameter(ln :: LineNumberNode, t)
    @switch t begin
        @case :($lb <: $(t::Symbol) <: $ub) || :($ub >: $(t::Symbol) >: $lb)
            TypeParamInfo(t, parse_type_repr(ln, lb), parse_type_repr(ln, ub))
        @case :($(t::Symbol) >: $lb)
            TypeParamInfo(t, parse_type_repr(ln, lb), _undefined)
        @case :($(t::Symbol) <: $ub)
            TypeParamInfo(t, _undefined, parse_type_repr(ln, ub))
        @case t::Symbol
            TypeParamInfo(t, _undefined, _undefined)
        @case _
            throw(create_exception(ln, "invalid type parameter $t"))
    end
end

function parse_function(ln :: LineNumberNode, ex; fallback :: T = _undefined,  allow_short_func :: Bool = false, allow_lambda :: Bool = false) where T
    self :: FuncInfo = FuncInfo()
    @switch ex begin
        @case Expr(:function, header, body)
            self.body = body
            self.isAbstract = false # unnecessary but clarified
            parse_function_header!(ln, self, header; allow_short_func = allow_short_func, allow_lambda = allow_lambda)
            return self
        @case Expr(:function, header)
            self.isAbstract = true
            parse_function_header!(ln, self, header; allow_short_func = allow_short_func, allow_lambda = allow_lambda)
            return self
        @case Expr(:(=), Expr(:call, _...) && header, rhs)
            self.body = rhs
            self.isAbstract = false
            parse_function_header!(ln, self, header; allow_short_func = allow_short_func, allow_lambda = allow_lambda)
            return self
        @case _
            if fallback isa Undefined
                throw(create_exception(ln, "invalid function expression: $ex"))
            else
                fallback
            end
    end
end

function parse_function_header!(ln::LineNumberNode, self::FuncInfo, header; allow_short_func :: Bool = false, allow_lambda :: Bool = false)

    self.typePars = typePars = TypeParamInfo[]

    @switch header begin
        @case Expr(:where, header, tyPar_exprs...) 
            for tyPar_expr in tyPar_exprs
                push!(typePars, parse_type_parameter(ln, tyPar_expr))
            end
        @case _
    end

    @switch header begin
        @case Expr(:(::), header, returnType)
            FuncInfo.returnType = returnType
        @case _
    end

    @switch header begin
        @case Expr(:call, f, Expr(:parameters, kwargs...), args...)
            for x in kwargs
                push!(self.kwPars, parse_parameter(ln, x))
            end
            for x in args
                push!(self.pars, parse_parameter(ln, x))
            end
            parse_function_header!(ln, self, f; allow_short_func = allow_short_func, allow_lambda = allow_lambda)
        @case Expr(:call, f, args...)
            for x in args
                push!(self.pars, parse_parameter(ln, x))
            end
            parse_function_header!(ln, self, f; allow_short_func = allow_short_func, allow_lambda = allow_lambda)
        @case Expr(:tuple, Expr(:parameters, kwargs...), args...)
            if !allow_lambda
                throw(create_exception(ln, "lambda functions are not supported, you may try parse_function(...; allow_lambda=true)."))
            end
            for x in kwargs
                push!(self.kwPars, parse_parameter(ln, x))
            end
            for x in args
                push!(self.pars, parse_parameter(ln, x))
            end
        @case Expr(:tuple, args...)
            if !allow_lambda
                throw(create_exception(ln, "lambda functions are not supported, you may try parse_function(...; allow_lambda=true)."))
            end
            for x in args
                push!(self.pars, parse_parameter(ln, x))
            end
        @case _
            self.name = header
    end
end
