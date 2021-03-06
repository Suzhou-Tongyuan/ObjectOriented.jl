## 类型不稳定 1：字段

mutable struct X
    a::Any
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


using BenchmarkTools

@btime sum1(xs)
#   147.800 μs (9489 allocations: 148.27 KiB)
10000

@btime sum2(xs)
#   5.567 μs (1 allocation: 16 bytes)
10000


# 如果想要检测性能问题，可以使用`@code_warntype`检测类型稳定性，
# 还可以用`@code_llvm`检测是否调用`jl_apply_generic`函数。
# 
# `@code_llvm sum1(xs)`或者 `code_llvm(sum1, (typeof(xs1), ))`:
#     可以发现存在 `jl_apply_generic`，这意味着动态分派。
#
# Julia动态分派的性能差，不如Python。

## 类型不稳定 2： 数组类型

using BenchmarkTools

function fslow(n)
    xs = [] # equals to 'Any[]'
    push!(xs, Ref(0))
    s = 0
    for i = 1:n
        xs[end][] = i
        s += xs[end][]
    end
    return s
end

function ffast(n)
    xs = Base.RefValue{Int}[]
    push!(xs, Ref(0))
    s = 0
    for i = 1:n
        xs[end][] = i
        s += xs[end][]
    end
    return s
end

@btime fslow(10000)
#   432.200 μs (28950 allocations: 452.44 KiB)
50005000

@btime ffast(10000)
#   4.371 μs (3 allocations: 144 bytes)
50005000


"""
class Ref:
    def __init__(self, x):
        self.x = x
def fpython(n):
    xs = []
    xs.append(Ref(0))
    s = 0
    for i in range(n):
        xs[-1].v = i
        s += xs[-1].v
    return s

%timeit fpython(10000)
# 1.03 ms ± 13.3 µs per loop (mean ± std. dev. of 7 runs, 1,000 loops each)
"""


# `InteractiveUtils.@code_warntype`可以发现类型不稳定的问题。黄色的代码表示可能存在问题，红色表示存在问题。


@code_warntype fslow(10000)
@code_warntype ffast(10000)

## 类型不稳定 3：类型不稳定的全局变量

int64_t = Int
float64_t = Float64
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

"""
scalar = 3
def sum_ints(xs):
    s = 0
    for x in xs:
        if isinstance(x, int):
            s += x
    return s

data = [1 if i % 2 == 0 else "2" for i in range(1, 1000001)]
%timeit sum_ints(data)
# 59.2 ms ± 2 ms per loop (mean ± std. dev. of 7 runs, 10 loops each)
"""

data = [i % 2 == 0 ? 1 : "2" for i = 1:1000000]

@btime sum_ints1(data)
#  18.509 ms (499830 allocations: 7.63 MiB)
1500000

@btime sum_ints2(data)
#  476.600 μs (1 allocation: 16 bytes)
1500000

## 可以用`@code_warntype`看到性能问题：

@code_warntype sum_ints1(data)
@code_warntype sum_ints2(data)


## 顶层作用域性能问题

xs = ones(Int, 1000000)
t0 = time_ns()
s = 0

for each in xs
    s += each
end
s
println("time elapsed: ", time_ns() - t0, "ns")
# time elapsed: 115_459_800ns

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
# time elapsed: 1_095_200ns
