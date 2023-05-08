module TestModule
using Test
using ObjectOriented

module structdef
    using ObjectOriented
    using Test
    using MLStyle: @match
    import InteractiveUtils

    function not_code_coverage_or_goto(e)
        @match e begin
            Expr(:meta, _...) => false
            Expr(:code_coverage_effect, _...) => false
            ::Core.GotoNode => false
            _ => true
        end
    end

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
            @mk begin
                a = a
                b = b
            end
        end

        function new(;a::Int, b::Int = 3) # new可以重载
            @mk begin
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
            @mk begin
                A(a, b)
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
        @property(a) do
            set
            get
        end
    end

    # 检查未实现的抽象方法
    # check unimplemented abstract methods
    @testset "interfaces 1" begin
        @test Set(keys(ObjectOriented.check_abstract(A3))) == Set([
            PropertyName(false, :interface_prop), # getter
            PropertyName(true, :interface_prop), # setter
            PropertyName(false, :interface_method2),
            PropertyName(false, :interface_method1)
        ])

        @test Set(keys(ObjectOriented.check_abstract(A4))) == Set([
            PropertyName(false, :a), # getter
            PropertyName(true, :a), # setter
        ])
    end

    # 'mutable' means 'classes'
    # 'mutable' 表示'类'
    @oodef mutable struct B34 <: {A3, A4}
        x :: Int
        function new(x)
            @mk begin
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

        @property(a) do
            set = (self, value) -> self.x = value
            get = (self) -> self.x
        end
    end

    @testset "interfaces 2" begin
        @test Set(keys(check_abstract(B34))) |> isempty
        b = B34(2)
        b.x = 3
        @test b.x === 3
        b.interface_prop = 10
        @test b.x === 9
        @test b.x == b.a
        b.a = 11
        @test b.x == 11
    end

    # can fetch a type's properties
    # 可以获取类型的properties
    @testset "propertynames" begin
        issubset(
            Set([:x, :a, :interface_method2, :interface_method1, :interface_prop]),
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
            @mk begin
                inner = collect(args)
            end
        end

        # constructor overloading
        # 重载构造器
        function new(vec :: Vector{T})
            self = new{T}()
            self.inner = vec
            return self
            # @mk begin
            #     inner = vec
            # end
        end

        function getindex(self, i::Integer)
            return @inbounds self.inner[i]
        end

        function setindex!(self, i::Integer, v::T)
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
            @test @match filter(not_code_coverage_or_goto, c.first.code)[2] begin
                Expr(:call, f, _...) && if f == GlobalRef(Base, :arrayref) end => true
                _ => false
            end
            @test length(filter(not_code_coverage_or_goto, c.first.code)) == 3
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

    @oodef struct TestPropertyInference
        @property(a) do
            get = self -> 1
        end

        @property(b) do
            get = self -> "str"
        end
    end

    x = TestPropertyInference()
    @testset "test inferencing properties" begin
        @test x.a == 1
        @test x.b == "str"
        @test (InteractiveUtils.@code_typed x.a).second in (Any, Union{Int, String})
        f(x) = @typed_access x.a
        @test Int == (InteractiveUtils.@code_typed f(x)).second
    end

    @oodef struct TestMissingParameterName{T}
        function new(::Type{T})
            new{T}()
        end
    end

    @testset "test missing parameter names" begin
        x = TestMissingParameterName(Int)
        @test x isa TestMissingParameterName{Int}
    end

    @oodef struct TestCurlyTypeApplication{T}
        function new()
            new{T}()
        end
    end

    @testset "test curly type application" begin
        x = TestCurlyTypeApplication{Int}()
        @test x isa TestCurlyTypeApplication{Int}
    end

    @testset "qualified field types" begin
        @oodef struct QualifiedFieldType
            b :: Core.Builtin
            @property(a) do
                get = self -> 1
            end
        end
    end

    @testset "blocks in struct" begin
        macro gen()
            quote
                a :: Int
                b :: Nothing
            end |> esc
        end
        @oodef struct TestBlockType
            @gen
            begin
                c :: Bool
                d :: Char
            end
        end
        TestBlockType(1, nothing, true, 'a')
    end

    z = "2"
    some_ref_val = Ref(2)
    @oodef struct TestDefaultFieldsImmutable
        a :: Int = 1
        b :: String = begin; some_ref_val[] = 1; repeat(z, 3) end
        function new()
            @mk
        end

        function new(b::String)
            @mk b = b
        end
    end

    @testset "default fields" begin
        x = TestDefaultFieldsImmutable()
        @test x.a == 1
        @test x.b == repeat(z, 3)
        @test some_ref_val[] == 1
        some_ref_val[] = 5
        x = TestDefaultFieldsImmutable("sada")
        @test some_ref_val[] == 5
        @test x.b == "sada"
    end
end

include("example.jl")
Example.DoPrint[] = false
Example.runtest()

include("inference.jl")
end