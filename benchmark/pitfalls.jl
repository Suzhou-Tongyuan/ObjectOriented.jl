#= Type Stability 1: field =#

mutable struct X
    a :: Any
end

xs = [X(1) for i = 1:10000]

function sum1(xs::AbstractVector{X})
    s = 0
    for x in xs
        s += x.a
    end
    return s
end

function sum2(xs::AbstractVector{X})
    s = 0
    for x in xs
        s += x.a :: Int
    end
    return s
end

@btime sum1(xs)
#   147.800 μs (9489 allocations: 148.27 KiB)
10000

@btime sum2(xs)
#   5.567 μs (1 allocation: 16 bytes)
10000


#= Type Stability 2: type =#

using BenchmarkTools

function fslow(n)
    xs = [] # equals to 'Any[]'
    push!(xs, Ref(0))
    s = 0
    for i in 1:n
        xs[end][] = i
        s += xs[end][]
    end
    return s
end

function ffast(n)
    xs = Base.RefValue{Int}[]
    push!(xs, Ref(0))
    s = 0
    for i in 1:n
        xs[end][] = i
        s += xs[end][]
    end
    return s
end



@btime fslow(10000)
@btime ffast(10000)

# julia> @btime fslow(10000)
#   432.200 μs (28950 allocations: 452.44 KiB)
# 50005000

# julia> @btime ffast(10000)
#   4.371 μs (3 allocations: 144 bytes)
# 50005000


# In [5]: class Ref:
#    ...:     def __init__(self, v):
#    ...:         self.v = v
#    ...:
#    ...: def f(n):
#    ...:     xs = []
#    ...:     xs.append(Ref(0))
#    ...:     s = 0
#    ...:     for i in range(n):
#    ...:         xs[-1].v = i
#    ...:         s += xs[-1].v
#    ...:     return s
#    ...:

# In [6]: f(100)
# Out[6]: 4950

# In [7]: %timeit f(10000)
# 1 ms ± 16.3 µs per loop (mean ± std. dev. of 7 runs, 1,000 loops each)

#= Type Stability 3: Referencing Non-constant Globals =#

int64_t = Int
scalar = 3

function sum_ints1(xs::Vector)
    s = 0
    for x in xs
        if x isa int64_t
            s += x * scalar
        end
    end
    return s
end

# const Int = Int
const const_scalar = 3
function sum_ints2(xs::Vector)
    s = 0
    for x in xs
        if x isa Int
            s += x * const_scalar
        end
    end
    return s
end

data = [i % 2 == 0 ? 1 : "2" for i = 1:1000000]
julia> @btime sum_ints1(data)
#  18.509 ms (499830 allocations: 7.63 MiB)
1500000

julia> @btime sum_ints2(data)
#  476.600 μs (1 allocation: 16 bytes)
1500000


#= Top level is slow =#

xs = ones(Int, 1000000)
t0 = time_ns()
s = 0
for each in xs
    s += each
end
s
println("time elapsed: ", time_ns() - t0, "ns")
# time elapsed: 115459800ns

@noinline test_loop(xs) = begin
    t0 = time_ns()
    s = 0
    for each in xs
        s += each
    end
    println("time elapsed: ", time_ns() - t0, "ns")
    return s
end
test_loop(xs) === 1000000
# time elapsed: 433500ns
