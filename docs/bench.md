### class

```julia
@oodef mutable struct Base1
    a :: Any
    function new(a::Any)
        @construct begin
            a = a
        end
    end

    function identity_a(self)
        self
    end
end

@oodef mutable struct Base2 <: Base1
    b :: Any
    function new(a::Any, b::Any)
        @construct begin
            @base(Base1) = Base1(a)
            b = b
        end
    end

    function identity_b(self)
        self
    end
end

@oodef mutable struct Base3 <: Base2
    c :: Any
    function new(a::Any, b::Any, c::Any)
        @construct begin
            @base(Base2) = Base2(a, b)
            c = c
        end
    end

    function identity_c(self)
        self
    end
end

@oodef mutable struct Base4 <: Base3
    d :: Any
    function new(a::Any, b::Any, c::Any, d::Any)
        @construct begin
            @base(Base3) = Base3(a, b, c)
            d = d
        end
    end

    function identity_d(self)
        self
    end
end

@oodef mutable struct Base5 <: Base4
    e :: Any
    function new(a::Any, b::Any, c::Any, d::Any, e::Any)
        @construct begin
            @base(Base4) = Base4(a, b, c, d)
            e = e
        end
    end

    function identity_e(self)
        self
    end
end

class_o = Base5(1, 2, 3, 4, 5)

@btime class_o.a
@btime class_o.b
@btime class_o.c
@btime class_o.d
@btime class_o.e
@btime class_o.identity_a()
@btime class_o.identity_b()
@btime class_o.identity_c()
@btime class_o.identity_d()
@btime class_o.identity_e()

# julia> @btime class_o.a
#   15.431 ns (0 allocations: 0 bytes)
# 1

# julia> @btime class_o.b
#   15.816 ns (0 allocations: 0 bytes)
# 2

# julia> @btime class_o.c
#   14.615 ns (0 allocations: 0 bytes)
# 3

# julia> @btime class_o.d
#   14.414 ns (0 allocations: 0 bytes)
# 4

# julia> @btime class_o.e
#   14.815 ns (0 allocations: 0 bytes)
# 5

# julia> @btime class_o.identity_a()
#   24.799 ns (1 allocation: 16 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime class_o.identity_b()
#   24.473 ns (1 allocation: 16 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime class_o.identity_c()
#   23.896 ns (1 allocation: 16 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime class_o.identity_d()
#   23.771 ns (1 allocation: 16 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))
```

### struct

```julia
@oodef struct Base1
    a :: Any
    function new(a::Any)
        @construct begin
            a = a
        end
    end

    function identity_a(self)
        self
    end
end

@oodef struct Base2 <: Base1
    b :: Any
    function new(a::Any, b::Any)
        @construct begin
            @base(Base1) = Base1(a)
            b = b
        end
    end

    function identity_b(self)
        self
    end
end

@oodef struct Base3 <: Base2
    c :: Any
    function new(a::Any, b::Any, c::Any)
        @construct begin
            @base(Base2) = Base2(a, b)
            c = c
        end
    end

    function identity_c(self)
        self
    end
end

@oodef struct Base4 <: Base3
    d :: Any
    function new(a::Any, b::Any, c::Any, d::Any)
        @construct begin
            @base(Base3) = Base3(a, b, c)
            d = d
        end
    end

    function identity_d(self)
        self
    end
end

@oodef struct Base5 <: Base4
    e :: Any
    function new(a::Any, b::Any, c::Any, d::Any, e::Any)
        @construct begin
            @base(Base4) = Base4(a, b, c, d)
            e = e
        end
    end

    function identity_e(self)
        self
    end
end

struct_o = Base5(1, 2, 3, 4, 5)

@btime struct_o.a
@btime struct_o.b
@btime struct_o.c
@btime struct_o.d
@btime struct_o.e
@btime struct_o.identity_a()
@btime struct_o.identity_b()
@btime struct_o.identity_c()
@btime struct_o.identity_d()
@btime struct_o.identity_e()

# julia> @btime struct_o.a
#   18.255 ns (0 allocations: 0 bytes)
# 1

# julia> @btime struct_o.b
#   18.136 ns (0 allocations: 0 bytes)
# 2

# julia> @btime struct_o.c
#   17.452 ns (0 allocations: 0 bytes)
# 3

# julia> @btime struct_o.d
#   17.836 ns (0 allocations: 0 bytes)
# 4

# julia> @btime struct_o.e
#   17.836 ns (0 allocations: 0 bytes)
# 5

# julia> @btime struct_o.identity_a()
#   35.146 ns (2 allocations: 96 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime struct_o.identity_b()
#   34.240 ns (2 allocations: 96 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime struct_o.identity_c()
#   35.484 ns (2 allocations: 96 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime struct_o.identity_d()
#   33.903 ns (2 allocations: 96 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime struct_o.identity_e()
#   33.736 ns (2 allocations: 96 bytes)
# Base5(5, Base4(4, Base3(3, Base2(2, Base1(1)))))

# julia> @btime (x -> x.a)(class_o)
#   11.900 ns (0 allocations: 0 bytes)
# 1

```


```python

class Base1:
    def __init__(self, a):
        self.a = a

    def identity_a(self):
        return self

class Base2(Base1):
    def __init__(self, a, b):
        super().__init__(a)
        self.b = b
        
    def identity_b(self):
        return self

class Base3(Base2):
    def __init__(self, a, b, c):
        super().__init__(a, b)
        self.c = c
        
    def identity_c(self):
        return self

class Base4(Base3):
    def __init__(self, a, b, c, d):
        super().__init__(a, b, c)
        self.d = d
        
    def identity_d(self):
        return self

class Base5(Base4):
    def __init__(self, a, b, c, d, e):
        super().__init__(a, b, c, d)
        self.e = e
        
    def identity_e(self):
        return self
    
o = Base5(1, 2, 3, 4, 5)

%timeit o.a
%timeit o.b
%timeit o.c
%timeit o.d
%timeit o.e

%timeit o.identity_a()
%timeit o.identity_b()
%timeit o.identity_c()
%timeit o.identity_d()
%timeit o.identity_e()

25.6 ns ± 0.114 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
27.1 ns ± 0.176 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
26.2 ns ± 0.0642 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
26.6 ns ± 0.142 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
31.2 ns ± 0.137 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
62.6 ns ± 0.578 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
59.5 ns ± 0.37 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
63.2 ns ± 1.01 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
63.7 ns ± 0.2 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
62.9 ns ± 0.568 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
```

### sum of concretely typed arrays

```julia
bases = [Base5(1, 2, 3, 4, 5) for i in 1:10000]
function sum_all(bases::Vector{<:@like(Base1)})
    s = 0
    for each in bases
        s += each.a # :: Int
    end
    s
end
@btime sum_all(bases)

# class:
# field is Int
# julia> @btime sum_all(bases)
#   19.900 μs (1 allocation: 16 bytes)


# field is Any, annotate s :: Int
# julia> @btime sum_all(bases)
#   25.900 μs (1 allocation: 16 bytes)

# field is Any, no annotations
# julia> @btime sum_all(bases)
#   152.800 μs (9489 allocations: 148.27 KiB)

# struct
# julia> @btime sum_all(bases)
#   140.900 μs (9489 allocations: 148.27 KiB)
#
# field is Any, Int annotations
# julia> @btime sum_all(bases)
#   6.640 μs (1 allocation: 16 bytes)
# 10000

# struct Int field
# julia> @btime sum_all(bases)
#   3.237 μs (1 allocation: 16 bytes)
# 10000

```



```python
bases = [Base5(1, 2, 3, 4, 5) for i in range(10000)]
def sum_all(bases):
    s = 0
    for each in bases:
        s += each.a
    return s
%timeit sum_all(bases)

#     ...: %timeit sum_all(bases)
# 410 µs ± 3.21 µs per loop (mean ± std. dev. of 7 runs, 1,000 loops each)
```