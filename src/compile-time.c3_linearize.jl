function fix_path(base, t, path)
    (t, (base, path...))
end

function cls_linearize(::Type{root}) where root
    bases = ObjectOriented.ootype_bases(root)
    chains = [[fix_path(base, t, path) for (t, path) in ObjectOriented.ootype_mro(base)] for base in bases]
    resolved = linearize(Tuple{Type, Tuple}, chains) do l, r
        l[1] === r[1]
    end
    insert!(resolved, 1, (root, ()))
    resolved
end

function cls_linearize(bases::Vector)::Vector{Tuple{Type, Tuple}}
    chains = [[fix_path(base, t, path) for (t, path) in ObjectOriented.ootype_mro(base)] for base in bases]
    linearize(Tuple{Type, Tuple}, chains) do l, r
        l[1] === r[1]
    end
end

function linearize(eq, ::Type{T}, xs::Vector) where T
    mro = T[]
    bases = T[K[1] for K in xs]
    xs = reverse!([reverse(K) for K in xs])
    while !isempty(xs)
        for i in length(xs):-1:1
            top = xs[i][end]
            for j in eachindex(xs)
                j === i && continue
                K = xs[j]
                for k = 1:length(K)-1
                    if eq(K[k], top)
                        @goto not_top
                    end
                end
            end
            push!(mro, top)
            for j in length(xs):-1:1
                K = xs[j]
                if eq(K[end], top)
                    pop!(K)
                    if isempty(K)
                        deleteat!(xs, j)
                    end
                end
            end
            @goto find_top
            @label not_top
        end
        error("Cannot create a consistent method resolution order (MRO) for $bases")
        @label find_top
    end
    return mro
end
