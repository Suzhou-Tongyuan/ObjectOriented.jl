import MacroTools
rmlines(x) = x

function rmlines(x::Expr)
  if x.head === :macrocall && length(x.args) >= 2
    Expr(x.head, x.args[1], x.args[2], filter(x->!MacroTools.isline(x), x.args[3:end])...)
  else
    Expr(x.head, filter(x->!MacroTools.isline(x), x.args)...)
  end
end

_striplines(ex) = MacroTools.prewalk(rmlines, ex)

# this is a duplicate of MacroTools.@q but avoid removing line numbers
# from macrocalls:
# see: https://github.com/FluxML/MacroTools.jl/blob/d1937f95a7e5c82f9cc3b5a4f8a2b33fdb32f884/src/utils.jl#L33
macro q(ex)
  # esc(Expr(:quote, ex))
  esc(Expr(:quote, _striplines(ex)))
end
