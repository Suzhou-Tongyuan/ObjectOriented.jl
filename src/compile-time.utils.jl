function extract_tbase(defhead)
    @switch defhead begin
        @case :($typename{$(generic_params...)})
            return (typename, generic_params)
        @case typename
            return (typename, [])
    end
end

extract_tvar(@nospecialize(var :: Union{Symbol, Expr}))::Symbol =
    @match var begin
        :($a <: $_) => a
        :($a >: $_) => a
        :($_ >: $a >: $_) => a
        :($_ <: $a <: $_) => a
        a::Symbol         => a
    end

extract_inheritance(@nospecialize(var)) =
    @match var begin
        :($head <: {$(t_bases...)}) => (head, Any[t_bases...])
        :($head <: $t_base) => (head, Any[t_base])
        head => (head, Any[])
    end


function canonicalize_where(ex::Expr)
    @switch ex begin
        @case Expr(:where, a)
            return canonicalize_where(a)
        @case Expr(head, args...)
            res = Expr(head)
            for arg in args
                push!(res.args, canonicalize_where(arg))
            end
            return res
    end
end

canonicalize_where(ex) = ex

struct ExprView
    getter
    setter
end

function Base.getindex(self::ExprView)
    return self.getter()
end

function Base.setindex!(self::ExprView, v)
    return self.setter(v)
end


function extract_funcname(@nospecialize(impl))
    @switch impl begin
        @case Expr(:function, defhead, _)
        @case _
            return nothing
    end
    @switch defhead begin
        @case :($defhead where {$(_...)})
        @case _
    end
    function mut_name(v)
        defhead.args[1] = v
    end
    function read_name()
        return defhead.args[1]
    end
    @match defhead begin
        :($_($(_...))) => ExprView(read_name, mut_name)
        :($_($(_...); $(_...))) => ExprView(read_name, mut_name)
        _ => nothing
    end
end


function apply_curly(t_base, t_args::AbstractVector)
    if isempty(t_args)
        t_base
    else
        :($t_base{$(t_args...)})
    end
end

function create_exception(ln::LineNumberNode, reason::String)
    LoadError(string(ln.file), ln.line, ErrorException(reason))
end
