module A
using ObjectOriented
using BenchmarkTools
const T = Any

@oodef struct Base1
    a :: T
    function new(a::T)
        @mk begin
            a = a
        end
    end

    function identity_a(self)
        self
    end
end

@oodef struct Base2 <: Base1
    b :: T
    function new(a::T, b::T)
        @mk begin
            @base(Base1) = Base1(a)
            b = b
        end
    end

    function identity_b(self)
        self
    end
end

@oodef struct Base3 <: Base2
    c :: T
    function new(a::T, b::T, c::T)
        @mk begin
            @base(Base2) = Base2(a, b)
            c = c
        end
    end

    function identity_c(self)
        self
    end
end

@oodef struct Base4 <: Base3
    d :: T
    function new(a::T, b::T, c::T, d::T)
        @mk begin
            @base(Base3) = Base3(a, b, c)
            d = d
        end
    end

    function identity_d(self)
        self
    end
end

@oodef struct Base5 <: Base4
    e :: T
    function new(a::T, b::T, c::T, d::T, e::T)
        @mk begin
            @base(Base4) = Base4(a, b, c, d)
            e = e
        end
    end

    function identity_e(self)
        self
    end
end

inst_o = Base5(1, 2, 3, 4, 5)

@info :struct
@btime inst_o.a
@btime inst_o.b
@btime inst_o.c
@btime inst_o.d
@btime inst_o.e
@btime inst_o.identity_a()
@btime inst_o.identity_b()
@btime inst_o.identity_c()
@btime inst_o.identity_d()
@btime inst_o.identity_e()

bases = [Base5(1, 2, 3, 4, 5) for i in 1:10000]

function sum_all(bases)
    s = 0
    for each in bases
        s += each.a :: Int
    end
    return s
end

using BenchmarkTools
@btime sum_all(bases)

end

module B
using ObjectOriented
using BenchmarkTools
const T = Any

@oodef mutable struct Base1
    a :: T
    function new(a::T)
        @mk begin
            a = a
        end
    end

    function identity_a(self)
        self
    end
end

@oodef mutable struct Base2 <: Base1
    b :: T
    function new(a::T, b::T)
        @mk begin
            @base(Base1) = Base1(a)
            b = b
        end
    end

    function identity_b(self)
        self
    end
end

@oodef mutable struct Base3 <: Base2
    c :: T
    function new(a::T, b::T, c::T)
        @mk begin
            @base(Base2) = Base2(a, b)
            c = c
        end
    end

    function identity_c(self)
        self
    end
end

@oodef mutable struct Base4 <: Base3
    d :: T
    function new(a::T, b::T, c::T, d::T)
        @mk begin
            @base(Base3) = Base3(a, b, c)
            d = d
        end
    end

    function identity_d(self)
        self
    end
end

@oodef mutable struct Base5 <: Base4
    e :: T
    function new(a::T, b::T, c::T, d::T, e::T)
        @mk begin
            @base(Base4) = Base4(a, b, c, d)
            e = e
        end
    end

    function identity_e(self)
        self
    end
end

inst_o = Base5(1, 2, 3, 4, 5)

@info :class
@btime inst_o.a
@btime inst_o.b
@btime inst_o.c
@btime inst_o.d
@btime inst_o.e
@btime inst_o.identity_a()
@btime inst_o.identity_b()
@btime inst_o.identity_c()
@btime inst_o.identity_d()
@btime inst_o.identity_e()


bases = [Base5(1, 2, 3, 4, 5) for i in 1:10000]

function sum_all(bases)
    s = 0
    for each in bases
        s += each.a :: Int
    end
    return s
end

using BenchmarkTools
@btime sum_all(bases)

end
