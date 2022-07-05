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

function try_pushmeta!(ex::Expr, sym::Symbol)
    Base.pushmeta!(ex, sym)
end

try_pushmeta!(a, sym::Symbol) = a
