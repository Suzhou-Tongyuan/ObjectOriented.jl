## TyOOP Cheat Sheet

TyOOP为Julia提供面向对象编程的功能，支持多继承、点操作符取成员、Python风格的properties以及接口编程。


### 1. 类型定义


定义不可变的OO结构体。

```julia
@oodef struct ImmutableData
    x :: Int
    y :: Int

    function new(x::Int, y::Int) 
        @mk begin
            x = x
            y = y
        end
    end
end

d = ImmutableData(1, 2)
x = d.x
```

其中，`new`是构造器函数。构造器和方法都可以重载。

`@mk`语句块产生当前类型的实例，在随后的语句块中，形如`a = b`是设置字段，形如`BaseClass(arg1, arg2)`是基类初始化。

定义可变的OO结构体（class）。

```julia
@oodef mutable struct MutableData
    x :: Int
    y :: Int

    function new(x::Int, y::Int) 
        @mk begin
            x = x
            y = y
        end
    end
end

mt = MutableData(1, 2)
mt.x += 1
```

### 2. 继承

```julia
@oodef mutable struct Animal
    name :: String
    function new(theName::String)
        @mk begin
            name = theName
        end
    end

    function move(self, distanceInMeters::Number = 0)
        println("$(self.name) moved $(distanceInMeters)")
    end
end

@oodef mutable struct Snake <: Animal
    function new(theName::String)
        @mk begin
            Animal(theName) # 初始化基类
        end
    end

    function snake_check(self)
        println("Calling a snake specific method!")
    end
end

sam = Snake("Sammy the Python")
sam.move()
# Sammy the Python moved 0
sam.snake_check()
# Calling a snake specific method!
```

此外，以下需要非常注意！

```julia
Snake <: Animal # false
Snake("xxx") isa Animal # false
```

记住，Julia原生类型系统并不理解两个class的子类型关系！详见[基于接口的多态抽象](#7-基于接口的多态抽象)。

你应该使用下列方法测试继承关系：
```julia
issubclass(Snake, Animal) # true
isinstance(Snake("xxx"), Animal) # true
Snake("xxx") isa @like(Animal) # true
```

### 4. Properties

```julia
@oodef mutable struct Square
    side :: Float64

    @property(area) do
        get = self -> self.side ^ 2
        set = (self, value::Number) -> self.side = convert(Float64, sqrt(value))
    end
end

square = Square()
square.side = 10
# call getter
square.area # 100.0

# call setter
square.area = 25
square.side # 5.0
```

### 5. 接口

接口类型，是大小为0(`sizeof(t) == 0`)的**不可变**OO类型。

接口类型实例的构造器是自动生成的，但也可以手动定义。

下面的`HasLength`是接口类型。

```julia
@oodef struct HasLength
    @property(len) do
        get  #= 抽象property: len =#
    end
end

@oodef struct Fillable
    function fill! end # 空函数表示抽象方法

    # 定义一个抽象的setter, 可以为全体元素赋值
    @property(allvalue) do
        set
    end
end

@oodef struct MyVector{T} <: {HasLength, Fillable}  # 多继承
    xs :: Vector{T}
    function new(xs::Vector{T})
        @mk begin
            xs = xs
        end
    end
end

check_abstract(MyVector)
# Dict{PropertyName, TyOOP.CompileTime.PropertyDefinition} with 3 entries:
#   fill! (getter)    => PropertyDefinition(:fill!, missing, :((Main).Fillable), MethodKind)
#   len (getter)      => PropertyDefinition(:len, missing, :((Main).HasLength), GetterPropertyKind)
#   allvalue (setter) => PropertyDefinition(:allvalue, missing, :((Main).Fillable), SetterPropertyKind)
```

`isempty(check_abstract(MyVector))`不为`true`，表示`MyVector`是抽象类型，需要实现相应属性或方法`len`, `fill!`和`allvalue`。


```julia
@oodef struct MyVector{T} <: {HasLength, Fillable}  # 多继承
    # 旧代码
    xs :: Vector{T}
    function new(xs::Vector{T})
        @mk begin
            xs = xs
        end
    end

    # 新增代码
    @property(len) do
        get = self -> length(self.xs)
    end

    @property(allvalue) do
        set = (self, value::T) -> fill!(self.xs, value)
    end

    function fill!(self, v::T)
        self.allvalue = v
    end
end

vec = MyVector([1, 2, 3])
vec.allvalue = 4
vec
# MyVector{Int64}([4, 4, 4], HasLength(), Fillable())
vec.len
# 3
vec.fill!(10)
vec
# MyVector{Int64}([10, 10, 10], HasLength(), Fillable())
```

此外，接口最重要的目的是基于接口的多态抽象。见下文[基于接口的多态抽象](#7-基于接口的多态抽象)。


### 6. 多继承

MRO(方法解析顺序)使用Python C3算法，所以多继承行为与Python一样。

```julia
@oodef struct A
    function calla(self) "A" end
    function call(self) "A" end
end

@oodef struct B <: A
    function callb(self) "B" end
    function call(self) "B" end
end

@oodef mutable struct C <: A
    function callc(self) "C" end
    function call(self) "C" end
end

@oodef struct D <: {A, C, B}
    function new()
        @mk begin
            A() # 可省略，因为A是接口类型
            B() # 可省略，因为B是接口类型
            C() # 不可省略，因为C是可变类型
            # 基类初始化可写成一行: A(), B(), C()
        end
    end
end

d = D()
d.calla() # A
d.callb() # B
d.callc() # C
d.call() # C
[x[1] for x in ootype_mro(typeof(d))]
# 4-element Vector{DataType}:
#  D
#  C
#  B
#  A
```

### 7. 基于接口的多态抽象


下面例子给出一个容易犯错的情况：

```julia
@oodef struct A end
@oodef struct B <: A end
myapi(x :: A) = println("do something!")

myapi(A())
# do something!

myapi(B())
# ERROR: MethodError: no method matching myapi(::B)
```

记住：Julia原生类型系统并不理解两个class的子类型关系！

如果希望Julia函数`myapi`的参数只接受A或A的子类型，应该这样实现：

```julia
myapi(x :: @like(A)) = println("do something!")

myapi(B())
# do something!

myapi([])
# ERROR: MethodError: no method matching myapi(::Vector{Any})
```


### 8. 一个机器学习的OOP实例

在下面这份代码里，我们实现一个使用最小二乘法训练的机器学习模型，并让其支持Julia中ScikitLearn的接口。通过下面代码，用户可以像使用一般ScikitLearn.jl的模型一样来调用这个模型，更可以在MLJ机器学习框架中使用这个模型，而不必关心该模型由面向对象还是多重分派实现。

```julia
using TyOOP

@oodef struct AbstractMLModel{X, Y}
    function fit! end
    function predict end
end

using LsqFit

@oodef mutable struct LsqModel{M<:Function} <: AbstractMLModel{Vector{Float64},Vector{Float64}}
    model::M  # 一个函数，代表模型的公式
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
xdata = collect(range(0, stop = 10, length = 20));
ydata = collect(model(xdata, ptrue) + 0.01 * randn(length(xdata)));

clf.fit!(xdata, ydata) # 训练模型
clf.predict(xdata)  # 预测模型
clf.param # 查看模型参数

# ScikitLearnBase提供了fit!和predict两个接口函数。
# 我们将TyOOP的接口(@like(...))和Julia接口对接。

using ScikitLearnBase
ScikitLearnBase.is_classifier(::@like(AbstractMLModel)) = true
ScikitLearnBase.fit!(clf::@like(AbstractMLModel{X, Y}), x::X, y::Y) where {X, Y} = clf.fit!(x, y)
ScikitLearnBase.predict(clf::@like(AbstractMLModel{X}), x::X) where X = clf.predict(x)

ScikitLearnBase.fit!(clf, xdata, ydata)
ScikitLearnBase.predict(clf, xdata)
```

### 9. 性能问题

TyOOP本身和Julia原生代码一样快，但由于递归调用点操作符运算`Base.getproperty`的类型推断问题 (例如[这个例子](https://discourse.julialang.org/t/type-inference-problem-with-getproperty/54585/2?u=thautwarm))，尽管大多数时候TyOOP编译出的机器码非常高效，但返回类型却忽然变成`Any`或某种`Union`类型。

这可能带来性能问题。出现该问题的情况是有限的，问题场合如下：

1. 使用Python风格的property
2. 在method里访问另一个成员，该成员再次递归调用点操作符

解决方案也很简单，使用`@typed_access`标注可能出现性能问题的代码即可。

```julia
@typed_access my_instance.method()
@typed_access my_instance.property
```

注意：上述代码中请保证`my_instance`类型已知。如果`@typed_access`标注的代码存在动态类型或类型不稳定，可能导致更严重的性能问题。
