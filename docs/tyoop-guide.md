# TyOOP

TyOOP为Julia提供一套完整的面向对象机制，方法上基于CPython的面向对象实现，对Julia做了适配。

其功能一览如下：

|  功能名   | 支持  | 注释 |
|:----:  | :----:  | :----: |
| 点操作符 | 是 | |
| 继承  | 是 | 基类、子类不能直接转换 |
| 构造器和实例方法重载 | 是 | 基于多重分派 |
| 多继承 | 是 | MRO基于扩展的C3算法 |
| Python风格 properties | 是 | |
| 泛型  | 是 |  |
| 接口 | 是 | 使用空结构体类型的基类 |
| 权限封装(modifiers)  | 否 | 同Python |
| 类静态方法  | 否 | 与Julia常规使用冲突，且易替代 |
| 元类(metaclass)        | 否 | 宏的下位替代，实际场景使用较少 |

## OO类型定义

TyOOP支持定义`class`和`struct`，`class`使用`@oodef mutable struct`开头，`struct`使用`@oodef struct`开头。

```julia
using TyOOP
@oodef struct MyStruct
    a :: Int
    function new(a::Int)
        @construct begin
            a = a
        end
    end
    function f(self)
        self.a
    end
end

@oodef mutable struct MyClass
    a :: Int
    function new(a::Int)
        @construct begin
            a = a
        end
    end
    function f(self)
        self.a
    end
end
```

## 类型构造器

上述代码中，`function new(...)`用于定义构造器。
构造器的返回值应当使用`@construct begin ... end`构造一个当前类型的实例，其中，`begin`语句块中使用`字段名=值`初始化字段。

缺省构造器的行为：
- 当类型为`class`，所有字段未初始化。
- 当类型为`struct`，且存在字段，使用Julia生成的构造器(`dataclass`)

构造器可以被重载。对于空间占用为0的结构体(单例类型)，构造器可以省略。

## 实例方法

实例方法须以`function 方法名(类实例, ...)`开头。类实例变量推荐写为`self`。

前面代码里`MyClass`和`MyStruct`都实现了实例方法`f`, 它们的实例，比方说`instance::MyClass`，以`instance.f()`的语法调用该方法。

```julia
@oodef mutable struct MyClass
    a :: Int
    # ... 省略部分定义
    function f(self)
        self.a
    end
end
```

实例方法支持任意形式的Julia参数，如变长参数，关键字参数，变长关键字参数，默认参数，默认关键字参数。

此外，实例方法支持泛型，且能被重载。

P.S: 如果要标注`self`参数的类型，应该使用`self :: @like(MyClass)`而不是`self :: MyClass`。这是因为实例方法可能被子类调用，而Julia不能支持隐式转换。

P.P.S: 什么是`@like`？对于一个OO类型`Parent`, 任何继承自`Parent`的子类`Child`满足`Child <: @like(Parent)`，其中`<:`是Julia原生的subtyping运算。

## 继承，多继承

下面是一个简单的继承例子。

首先我们定义两个结构体类型。

```julia
@oodef struct A
    a :: Int
end

@oodef struct B
    b :: Int
end
```

随后，我们用一个类型`C`继承上面两个类型。
```julia
@oodef struct C <: {A, B}
    c :: String
    function new(a::Int, b::Int, c::String = "somestring")
        @construct begin
            @base(A) = A(a)
            @base(B) = B(b)
            c = c
        end
    end
end

c = C(1, 2)
@assert c.a === 1
@assert c.b === 2
```

可以看到，我们使用在`@construct`块中使用`@base(A) = ...`来设置基类，这和Python中的`基类.__init__(self, args...)`一致。

一个子类可以继承多个基类，当多个基类出现重名属性时，使用C3线性化算法进行method resolution。

下面这个例子给了一种常见的继承应用方式： Mixin。

我们定义一个基类，多边形`IPolygon`，它的子类可能有正方形、长方形、三角形乃至一般的多边形，但这些子类都共享一个标准的周长求解算法：将所有边的长度相加。

则多边形的基类，可以用如下代码定义：

```julia
using TyOOP

const Point = Tuple{Float64, Float64}
function distance(source::Point, destination::Point)
    sqrt(
        (destination[1] - source[1]) ^ 2 +
        (destination[2] - source[2]) ^ 2)
end

@oodef struct IPolygon
    # 抽象方法
    function get_edges end

    # mixin方法
    function get_perimeter(self)
        s = 0.0
        vs = self.get_edges() :: AbstractVector{Point}
        if length(vs) <= 1
            0.0
        end
        last = vs[1] :: Point
        for i = 2:length(vs)
            s += distance(vs[i], last)
            last = vs[i]
        end
        s += distance(vs[end], vs[1])
        return s
    end
end
```

利用上述基类`IPolygon`，我们可以实现子类，并复用其中的`get_perimeter`方法。

例如，矩形`Rectangle`：

```julia
@oodef struct Rectangle <: IPolygon
    width :: Float64
    height :: Float64
    center :: Point

    function new(width::Float64, height::Float64, center::Point)
        @construct begin
            width = width
            height = height
            center = center
        end
    end

    function get_edges(self)
        x0 = self.center[1]
        y0 = self.center[2]
        h = self.height / 2
        w = self.width / 2
        Point[
            (x0 - w, y0 - h),
            (x0 - w, y0 + h),
            (x0 + w, y0 + h),
            (x0 + w, y0 - h)
        ]
    end

    # 对特殊的子类，可以重写 get_perimeter 获得更快的求周长方法
    # function get_perimeter() ... end
end

rect = Rectangle(3.0, 2.0, (5.0, 2.0))
@assert Arect.get_perimeter() == 10.0
```

P.S: 由TyOOP定义的OO类型，只能继承其他OO类型。

## Python风格的properties

在Java中，getter函数(`get_xxx`)和setter(`set_xxx`)函数用来隐藏类型字段的实现细节。

对于其中冗余，很多语言如Python提供了一种语法糖，允许抽象`self.xxx`和`self.xxx = value`，这就是property。

TyOOP支持property，有两种方式：

第一种方式是定义`get_xxx`和`set_xxx`函数，这适合Java背景的工作人员过渡：

```julia
@oodef struct DemoProp
    function get_value(self)
        return 100
    end
    function set_value(self, value)
        println("setting $value")
    end
end

# Java风格的getter, setter
println(DemoProp().get_value()) # => 100

DemoProp().set_value(200) # => setting 200
```

与此同时，`get_xxx`会自动定义Python风格的getter property。

```julia
DemoProp().value # => 100
```

`set_xxx`则会定义Python风格的setter property。

```julia
DemoProp().value = 200 # => setting 200
```

当熟悉这种抽象后，可以使用第二种方式，这适合Python、C#等背景的工作人员：

```julia
@oodef mutable struct Square
    side :: Float64
    function new(side::Number)
        @construct begin
            side = convert(Float64, side)
        end
    end

    @property(area) do
        get = self -> self.side ^ 2
        set = function (self, value)
            self.side = sqrt(value)
        end
    end
end

square = Square(5) # => Square(5.0)
square.area # => 25.0
square.area = 16 # => 16
square.side # => 4.0
```

可以看到，在设置面积的同时，正方形的边长得到相应改变。

## 高级特性：抽象方法和抽象property

```julia
@oodef struct AbstractSizedContainer{ElementType}

    # 定义一个抽象方法
    function contains end

    
    # 定义一个抽象getter
    @property(length) do
        get
    end
    # 也可以定义抽象方法 'get_length'
end

# 打印未实现的方法（包括property）
TyOOP.check_abstract(AbstractSizedContainer)
# =>
# Dict{PropertyName, TyOOP.CompileTime.PropertyDefinition} with 2 entries:
#  contains (getter) => PropertyDefinition(:contains, missing, AbstractSizedContainer, MethodKind)
#  length (getter)   => PropertyDefinition(:length, missing, AbstractSizedContainer, GetterPropertyKind)

@oodef struct MyNumSet{E <: Number} <: AbstractSizedContainer{E}
    inner :: Set{E}
    function new(args::E...)
        @construct begin
            inner = Set{E}(args)
        end
    end

    # if no annotations for 'self',
    # annotations and type parameters can be added like:
    # 'function contains(self :: @like(MySet{E}), e::E) where E' 
    function contains(self, e::E)
        return e in self.inner
    end
    
    @property(length) do
        get = self -> length(self.inner)
    end
end

my_set = MySet(1, 2, 3)
my_set.length # => 3
my_set.contains(2) # => true
```

## 高级特性：泛型

泛型无处不在，业务中常见于容器。

在[抽象方法](#高级特性抽象方法和抽象property)一节，我们介绍了`AbstractSizedContainer`，可以看到它有一个泛型参数`ElementType`。

```julia
@oodef struct AbstractSizedContainer{ElementType}
    function contains end
    function get_length end
end
```

虽然在定义时没有用到这个类型，但在子类定义时，该类型参数能用来约束容器的元素类型。

TyOOP能使用各种形式的Julia泛型，下面是一些例子。
```julia
# 数字容器
@oodef struct AbstactNumberContainer{ElementType <: Number}
    ...
end

# 用来表示任意类型的可空值
@oodef struct Optional{T}
    value :: Union{Nothing, Some{T}}
end
```

## 高级特性：接口

TyOOP支持接口编程：使用`@oodef struct`定义一个没有字段的结构体类型，为它添加一些抽象方法，这样就实现了接口。

除开业务上方便对接逻辑外，接口还能帮助抽象。

下面的代码基于接口`HasLength`定义一个普通的Julia函数`a_regular_julia_function`：

```julia
@oodef struct HasLength
    function get_length end
end

function a_regular_julia_function(o :: @like(HasLength))
    function some_random_logic(i::Integer)
        (i * 3 + 5) ^ 2
    end
    some_random_logic(o.get_length()) # 或者 o.length
end
```

其中，`@like`宏作用将实际类型变成接口类型。

在Julia的类型系统和多重分派中，具体的Julia类型不能被继承；而`@like(ootype)`唯一地将类型`ootype`转为Julia类型系统中能被继承的抽象类型，使得我们的OO系统能和Julia的多重分派一同工作。~~这是本项目的主要含金量。~~


现在，我们为`HasLength`实现一个子类`MyList`，作为`Vector`类型的包装：

```julia
@oodef struct MyList{T} <: HasLength
    inner :: Vector{T}
    
    function new(elts::T...)
        @construct begin
            inner = collect(T, elts)
        end
    end

    function get_length(self)
        length(self.inner)
    end
end

a_regular_julia_function(MyList(1, 2, 3)) # 196
a_regular_julia_function([1]) # error
```

可以看到，只有实现了HasLength的OO类型可以应用`a_regular_julia_function`。

此外，我们指出，对于一个功能，如果在原生Julia实现下没有性能损失，TyOOP的接口编程也同样能不产生性能损失。

```julia
@code_typed a_regular_julia_function(MyList(1, 2, 3))
CodeInfo(
1 ─ %1 = (getfield)(o, :inner)::Vector{Int64}
│   %2 = Base.arraylen(%1)::Int64
│   %3 = Base.mul_int(%2, 3)::Int64
│   %4 = Base.add_int(%3, 5)::Int64
│   %5 = Base.mul_int(%4, %4)::Int64
└──      return %5
) => Int64

julia> @code_llvm a_regular_julia_function(MyList(1, 2, 3))
;  @ REPL[6]:1 within `a_regular_julia_function`
; Function Attrs: uwtable
define i64 @julia_a_regular_julia_function_1290({ {}* }* nocapture nonnull readonly align 8 dereferenceable(8) %0) #0 {
top:
    %1 = bitcast { {}* }* %0 to { i8*, i64, i16, i16, i32 }**
    %2 = load atomic { i8*, i64, i16, i16, i32 }*, { i8*, i64, i16, i16, i32 }** %1 unordered, align 8
    %3 = getelementptr inbounds { i8*, i64, i16, i16, i32 }, { i8*, i64, i16, i16, i32 }* %2, i64 0, i32 1
    %4 = load i64, i64* %3, align 8
    %5 = mul i64 %4, 3
    %6 = add i64 %5, 5
    %7 = mul i64 %6, %6
  ret i64 %7
}
```

P.S: 为接口增加默认方法可以实现著名的Mixin抽象。见[继承，多继承](#继承多继承)中的`IPolygon`类型。

## `@typed_access`

Julia点操作符实际上是`getproperty/setproperty!`，因为编译器优化原因，使用Python风格的property会导致类型推导不够精准，降低性能。
对于可能的性能损失，我们提供`@typed_access`宏，在兼容julia原生语义的条件下，自动优化所有的`a.b`操作。

```julia
@typed_access begin
    instance1.method(instance2.property)
end

# 等价于

TyOOP.typed_access(instance1, Val(:method))(
    TyOOP.typed_access(instance, Val(:property))
)
```

`@typed_access`让动态分派更慢，让静态分派更快。对于`a.b`，如果`a`的类型被Julia成功推断，则`@typed_access a.b`不会比`a.b`慢。

## Benchmark

我们使用class或struct做嵌套继承，并测试访问基类字段、方法的性能。property是方法语法糖，因此不单独进行测试。

类型hierarchy:

- Base1
  - 字段: `a`
  - 方法: `identity_a`(返回实例本身)
  - 子类: Base2
    - 字段: `b`
    - 方法: `identity_b`(返回实例本身)
    - 子类: Base3
      - 字段: `c`
      - 方法: `identity_c`(返回实例本身)
      - 子类: Base4
        - 字段: `d`
        - 方法: `identity_d`(返回实例本身)
        - 子类: Base5
          - 字段: `e`
          - 方法: `identity_e`(返回实例本身)


测试结果：

|  测试例子   | class或struct或Python class  | 运行时间 | 说明 |
|:----:  | :----:  | :----: |:----:|
| 获取最顶层基类字段 | class | 15.4 ns |  |
| 获取最顶层基类字段 | struct | 18.3 ns |  |
| 获取最顶层基类字段 | Python class | 25.6 ns |  inline cache，平均常数时间访问字段 |
| 调用最顶层方法     | class | 24.8 ns  |  |
| 调用最顶层方法 | struct | 35.2 ns |  |
| 调用最顶层方法     | Python class | 63.2 ns  | inline cache，平均常数时间访问方法 |
| 数组获取基类字段并求和 | class | 19.9 us | |
| 数组获取基类字段并求和 | struct | 6.64 us | |
| 数组获取基类字段并求和 | Python class | 410 us | |

注：当使用原生Julia时，连续字段访问与TyOOP访问基类字段，无性能差异；对于方法访问，将实例作为参数直接传递给对应类方法，性能等同于TyOOP的方法调用相同，无论方法是否嵌套。这说明使用TyOOP有助于更方便地达到Julia最佳性能。
