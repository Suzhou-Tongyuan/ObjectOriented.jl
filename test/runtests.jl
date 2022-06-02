module TestModule
using Test
using TyOOP

module structdef
    using TyOOP
    using Test
    using MLStyle: @match
    import InteractiveUtils

    # Julia's default constructor are used for structs that have fields
    # 当结构体存在字段，使用Julia默认的构造器
    @oodef struct A
        a :: Int
        b :: Int
    end
    @testset "default struct constructor" begin
        a = A(1, 2)
        @test a.a == 1
        @test a.b == 2
    end

    # custom constructors are allowed for such case
    # 这种情况下，也允许自定义构造器
    @oodef struct A2
        a :: Int
        b :: Int
        function new(a::Int, b::Int = 3) # new用来定义OO类型的构造器
            @construct begin 
                a = a 
                b = b
            end
        end

        function new(;a::Int, b::Int = 3) # new可以重载
            @construct begin 
                a = a 
                b = b
            end
        end
    end

    @testset "custom struct constructor with default arguments/keyword arguments" begin
        a = A2(1)
        @test a.a == 1
        @test a.b == 3
        a = A2(a=1)
        @test a.a == 1
        @test a.b == 3
    end

    # struct can be used as a base class
    # 结构体可以作为基类
    @oodef struct B <: A
        c :: Int
        function new(a :: Int, b :: Int, c :: Int)
            @construct begin
                @base(A) = A(a, b)
                c = c
            end
        end
    end

    @testset "struct inherit struct" begin
        b = B(1, 2, 3)
        @test b.a == 1
        @test b.b == 2
        @test b.c == 3        
    end
    
    # empty structs and inheritances need no custom constructors
    # 空结构体和其继承不需要自定义构造器
    @oodef struct A3
        function interface_method1 end
        function interface_method2 end
        @property(interface_prop) do
            set
            get
        end
    end
    
    @oodef struct A4

        # get_xxx generates a getter xxx
        # get_xxx 自动生成getter xxx
        function get_a end
        # set_xxx 自动生成setter xxx
        function set_a end
    end

    # 检查未实现的抽象方法
    # check unimplemented abstract methods
    @testset "interfaces 1" begin
        @test Set(keys(TyOOP.check_abstract(A3))) == Set([
            PropertyName(false, :interface_prop), # getter
            PropertyName(true, :interface_prop), # setter
            PropertyName(false, :interface_method2),
            PropertyName(false, :interface_method1)
        ])

        @test Set(keys(TyOOP.check_abstract(A4))) == Set([
            PropertyName(false, :a), # getter
            PropertyName(true, :a), # setter
            PropertyName(false, :get_a),
            PropertyName(false, :set_a)
        ])
    end

    # 'mutable' means 'classes'
    # 'mutable' 表示'类'
    @oodef mutable struct B34 <: {A3, A4}
        x :: Int
        function new(x)
            @construct begin
                #= empty struct bases can be omitted: =#
                #= 空结构体基类可以省略： =#
                # @base(A3) = A3()
                # @base(A4) = A4()
                x = x
            end
        end

        function interface_method1(self)
            println(1)
        end

        function interface_method2(self)
            println(1)
        end

        @property(interface_prop) do
            set = function (self, value)
                self.x = value - 1
            end
            get = function (self)
                return self.x + 1
            end
        end

        function set_a(self, value)
            self.x = value
        end

        function get_a(self, value)
            self.x = value
        end
    end

    @testset "interfaces 2" begin
        @test Set(keys(check_abstract(B34))) |> isempty
        b = B34(2)
        b.x = 3
        @test b.x === 3
        b.interface_prop = 10
        @test b.x === 9
    end

    # can fetch a type's properties
    # 可以获取类型的properties
    @testset "propertynames" begin
        issubset(
            Set([:x, :a, :interface_method2, :interface_method1, :interface_prop, :get_a, :set_a]),
            Set(propertynames(B34)))
    end

    # work with julia stdlib
    # 能和Julia标准库一同工作
    @oodef struct IRandomIndexRead{IndexType}
        function getindex end
    end

    @oodef struct IRandomIndexWrite{IndexType, ElementType}
        function setindex! end
    end

    Base.@inline function Base.getindex(x::@like(IRandomIndexRead{>:I}), i::I) where I
        x.getindex(i)
    end

    Base.@inline function Base.setindex!(x::@like(IRandomIndexWrite{>:I, >:E}), i::I, value::E) where {I, E}
        x.setindex!(i, value)
    end

    @oodef struct MyVector{T} <: {IRandomIndexRead{Integer}, IRandomIndexWrite{Integer, T}}
        inner :: Vector{T}
        
        function new(args :: T...)
            @construct begin
                inner = collect(args)
            end
        end
        
        # constructor overloading
        # 重载构造器
        function new(vec :: Vector{T})
            @construct begin
                inner = vec
            end
        end

        function getindex(self, i::Integer)
            return @inbounds self.inner[i]
        end

        function setindex!(self, i::Integer, v::T) where T
            @inbounds self.inner[i] = v
        end
    end

    @testset "interface programming is multiple-dispatch compatible" begin
        # 接口编程与多重派发兼容
        myvec = MyVector(1, 2, 3, 5)
        setindex!(myvec, 2, 3)
        @test getindex(myvec, 2) == 3
        
        # 代码被优化到最佳形式
        @testset "code optimization" begin
            c = InteractiveUtils.@code_typed getindex(myvec, 2)
            @info :optimized_code c
            # │   c =
            # │    CodeInfo(
            # │    1 ─ %1 = (getfield)(x, :inner)::Vector{Int64}
            # │    │   %2 = Base.arrayref(true, %1, i)::Int64
            # │    └──      return %2
            # └    ) => Int64
            @test c.second === Int
            @test @match c.first.code[2] begin
                Expr(:call, f, _...) && if f == GlobalRef(Base, :arrayref) end => true
                _ => false
            end
            @test length(c.first.code) == 3
        end
    end

    @oodef struct OverloadedMethodDemo
        function test(self, a::Int)
            "Int $a"
        end
        function test(self, a, b)
            "2-ary"
        end
    end
    @testset "overloading" begin
        @test OverloadedMethodDemo().test(1) == "Int 1"
        @test OverloadedMethodDemo().test(1, 2) == "2-ary"
    end
end

include("example.jl")
Example.DoPrint[] = false
Example.runtest()

end