using ObjectOriented

## 定义类
@oodef mutable struct MyClass
    attr::Int

    function new(arg::Int)

        # @mk宏：设置字段和基类
        @mk begin
            attr = arg
        end
    end

    function f(self)
        return self.attr
    end
end

c = MyClass(1)
c.attr

c.f()

@code_typed c.f()

## 继承

@oodef mutable struct MySubclass <: MyClass
    attr::Int # shadowing
    function new(attr_base, attr)
        a = attr + 1
        @mk begin
            @base(MyClass) = MyClass(attr_base)
            attr = a
        end
    end

    function base_f(self)
        get_base(self, MyClass).f()
    end
end


sc = MySubclass(100, 200)
sc.attr
sc.f()
sc.base_f()

@code_typed sc.base_f()

## 多继承和MRO

@oodef struct Base1
    function func(self)
        return "call base1"
    end
end

@oodef struct Base2 <: Base1
    function func(self)
        return "call base2"
    end
end

@oodef struct Base3 <: Base1
    function func(self)
        return "call base3"
    end

    function base3_func(self)
        return "special: call base3"
    end
end

@oodef struct Sub1 <: {Base2, Base3} end

Sub1().func()

Sub1().base3_func()
get_base(Sub1(), Base3).func()

## properties

@oodef mutable struct Square
    area::Float64

    function new(area::Number)
        @mk begin
            area = convert(Float64, area)
        end
    end

    #= setter, getter
    function get_side(self)
        return sqrt(self.area)
    end

    function set_side(self, value::Number)
        self.area = convert(Float64, value)^2
    end
    =#

    # explicit property
    @property(side) do
        get = self -> sqrt(self.area)
        set = (self, value) -> self.area = convert(Float64, value)^2
    end
end

sq = Square(25)
sq.side
sq.side = 4
sq.area
sq.area = 36
sq.area = 36.0
sq.side

## 泛型和接口

using ObjectOriented

@oodef struct AbstractMLModel{X, Y}
    function fit! end
    function predict end
end

using LsqFit

@oodef mutable struct LsqModel{M<:Function} <: AbstractMLModel{Vector{Float64},Vector{Float64}}
    model::M
    param::Vector{Float64}
    function new(m::M, init_param::Vector{Float64})
        @mk begin
            model = m
            param = init_param
        end
    end

    function fit!(self, X::Vector{Float64}, y::Vector{Float64})
        fit = curve_fit(self.model, X, y, self.param)
        self.param = fit.param
        self
    end

    function predict(self, x::Float64)
        self.predict([x])
    end

    function predict(self, X::Vector{Float64})
        return self.model(X, self.param)
    end
end

# 例子来自 https://github.com/JuliaNLSolvers/LsqFit.jl
@. model(x, p) = p[1] * exp(-x * p[2])
clf = LsqModel(model, [0.5, 0.5])
ptrue = [1.0, 2.0]
xdata = collect(range(0, stop = 10, length = 20))
ydata = collect(model(xdata, ptrue) + 0.01 * randn(length(xdata)))
clf.fit!(xdata, ydata)
clf.predict(xdata)
clf.param

# 比如ScikitLearnBase提供了fit!函数和predict函数

using ScikitLearnBase
ScikitLearnBase.is_classifier(::@like(AbstractMLModel)) = true
ScikitLearnBase.fit!(clf::@like(AbstractMLModel{X, Y}), x::X, y::Y) where {X, Y} = clf.fit!(x, y)
ScikitLearnBase.predict(clf::@like(AbstractMLModel{X}), x::X) where X = clf.predict(x)

ScikitLearnBase.fit!(clf, xdata, ydata)
ScikitLearnBase.predict(clf, xdata)

# 一些辅助函数

isinstance(clf, LsqModel)
isinstance(clf, AbstractMLModel)
issubclass(LsqModel, AbstractMLModel)

function f2(_::@like(AbstractMLModel))
end

## Julia类型标注不支持子类、父类转换（Python没有type assertion，不需要写标注），要使用@like宏支持接口参数
