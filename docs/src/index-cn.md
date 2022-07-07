```@meta
CurrentModule = TyOOP
```

# TyOOP

[TyOOP](https://github.com/thautwarm/TyOOP.jl)为Julia提供一套相对完整的面向对象机制，设计上主要基于CPython的面向对象，对Julia做了适配。

其功能一览如下：

|  功能名   | 支持  | 注释 |
|:----:  | :----:  | :----: |
| 点操作符 | 是 | |
| 继承  | 是 | 基类、子类不能直接转换 |
| 构造器和实例方法重载 | 是 | 基于多重分派 |
| 多继承 | 是 | MRO基于变种[C3算法](https://en.wikipedia.org/wiki/C3_linearization) |
| Python风格 properties | 是 | |
| 默认字段 | 是 | |
| 泛型  | 是 |  |
| 接口 | 是 | 使用空结构体类型做基类 |
| 权限封装(modifiers)  | 否 | 同Python |
| 类静态方法  | 否 | 不实现，避免[type piracy](https://docs.julialang.org/en/v1/manual/style-guide/#Avoid-type-piracy) |
| 元类(metaclass)        | 否 | 不实现，推荐宏处理 |

快速学习请参考[TyOOP Cheat Sheet](./cheat-sheet-cn.md).

必须强调的是，我们非常认可Julia社区关于“不要在Julia中做OOP”的观点。

我们创建这个指南 **[将OOP翻译到地道的Julia]((./how-to-translate-oop-into-julia.md))**，以指导用户如何将OOP代码翻译为更简短、更高效的Julia代码。

我们更是花费精力将TyOOP设计成这个样子：OOP的使用能被局限在坚定的OOP使用者的代码里，通过接口编程，这些OOP代码和正常的Julia对接，以避免不合适的代码在外部泛滥。

## OO类型定义

TyOOP支持定义class和struct，class使用`@oodef mutable struct`开头，struct使用`@oodef struct`开头。

```julia
using TyOOP
@oodef struct MyStruct
    a :: Int
    function new(a::Int)
        @mk begin
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
        @mk begin
            a = a
        end
    end
    function f(self)
        self.a
    end
end
```

上述代码中，`function new(...)`用于定义构造器。
构造器的返回值应当使用`@mk begin ... end`构造一个当前类型的实例，其中，`begin`语句块中使用`字段名=值`初始化字段。

缺省构造器的行为：
- 当类型为`class`，所有字段未初始化。
- 当类型为`struct`，且存在字段，使用Julia生成的构造器(`dataclass`)

构造器可以被重载。对于空间占用为0的结构体(单例类型)，构造器可以省略。

### 实例方法

实例方法须以`function 方法名(类实例, ...)`开头。类实例变量推荐命名为`self`或`this`。

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

### 默认字段

TyOOP支持默认字段。

在为类型定义一个字段时，如果为这个字段指定默认值，那么`@mk`宏允许缺省该字段的初始化。注意，如果不定义`new`函数并使用`@mk`宏，默认字段将无效。

```julia
function get_default_field2()
    println("default field2!")
    return 30
end

@oodef struct MyType
    field1 :: DataType = MyType
    field2 :: Int = get_default_field2()

    function new()
        return @mk
    end

    function new(field2::Integer)
        return @mk field2 = field2
    end
end

julia> MyType()
default field2!
MyType(MyType, 30)

julia> MyType(50)
MyType(MyType, 50)
```

关于默认字段的注意点：

1. 默认字段没有性能开销。
2. 在`@mk`块显式指定字段初始化时，默认字段的求值表达式不会被执行。
3. 与`Base.@kwdef`不同，默认字段的求值表达式无法访问其他字段。



## Python风格的构造器

以往的OO语言，如Python/C++/Java/C#，没有原生支持的不可变类型，因此构造器的工作一般设计为：
1. 创建一个新对象`self`(或this)
2. 利用构造器参数对`self`进行初始化

Julia也支持这样的构造方式，但只对`mutable struct`有效，且不推荐。写法如下:

```julia
@oodef mutable struct MySubclass <: {MySuperclass1, MySuperclass2}
    field1
    function new()
        self = @mk
        # 初始化字段
        self.field1 = 1
        ## 记住需要返回
        return self
    end
```



## [继承，多继承](@id inheritance_cn)

下面是一个简单的继承例子。

首先我们用`@oodef`定义两个结构体类型:

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
        @mk begin
            A(a), B(b)
            c = c
        end
    end
end

c = C(1, 2)
@assert c.a === 1
@assert c.b === 2
```

可以看到，我们使用在`@mk`块中使用`Base1(arg1, arg2), Base2(arg1, arg2)`来设置基类，这和Python中的`基类.__init__(self, args...)`一致。

一个子类可以继承多个基类，当多个基类出现重名属性时，使用C3线性化算法来选取成员。我们使用的C3算法是一个变种，能允许更灵活的mixin抽象。

下面给出一个mixin的例子。mixin是继承的一种常见应用：

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
        @mk begin
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
@assert rect.get_perimeter() == 10.0
```

P.S: 由TyOOP定义的OO类型，只能继承其他OO类型。

## Python风格的properties

在Java中，getter函数(`get_xxx`)和setter(`set_xxx`)函数用来隐藏实现细节，暴露稳定的API。

对于其中冗余，很多语言如Python提供了一种语法糖，允许抽象`self.xxx`和`self.xxx = value`，这就是property。

TyOOP支持property，用以下的方式：

```julia
@oodef struct DemoProp
    @property(value) do
        get = self -> 100
        set = (self, value) -> println("setting $value")
    end
end

println(DemoProp().value) # => 100
DemoProp().value = 200 # => setting 200
```

下面是一个更加实际的例子：

```julia
@oodef mutable struct Square
    side :: Float64
    function new(side::Number)
        @mk begin
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

## [高级特性：抽象方法和抽象property](@id advanced_absmeths_and_absprops_cn)

```julia
@oodef struct AbstractSizedContainer{ElementType}

    # 定义一个抽象方法
    function contains end


    # 定义一个抽象getter
    @property(length) do
        get
    end
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
        @mk begin
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

在[抽象方法](@ref advanced_absmeths_and_absprops_cn)一节，我们介绍了`AbstractSizedContainer`，可以看到它有一个泛型参数`ElementType`。

```julia
@oodef struct AbstractSizedContainer{ElementType}
    # (self, ::ElementType) -> Bool
    function contains end
    function get_length end
end
```

虽然在定义时没有用到这个类型，但在子类定义时，该类型参数能用来约束容器的元素类型。

TyOOP支持各种形式的Julia泛型，下面是一些例子。

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

### 高级特性：显式泛型类型参数

下面的代码给出一个特别的例子，构造器`new`无法从参数类型推断出泛型类型参数`A`。

```julia
@oodef struct MyGenType{A}
    a :: Int
    function new(a::Int)
        new{A}(a)
    end
end
```

在这种情况下，可以显式指定泛型类型参数，构造类型实例：

```julia
my_gen_type = MyGenType{String}(1)
my_gen_type = MyGenType{Number}(1)
my_gen_type = MyGenType{Vector{Int}}(1)
```

## 高级特性：接口

TyOOP支持接口编程：使用`@oodef struct`定义一个没有字段的结构体类型，为它添加一些抽象方法，这样就实现了接口。

除开业务上方便对接逻辑外，接口还能为代码提供合适的约束。

### `@like(ootype)`


`@like` 将具体的OO类型转为某种特殊的Julia抽象类型。

```julia
julia> @like(HasLength)
Object{>:var"HasLength::trait"}
```

在Julia的类型系统中，具体类型不能被继承。其直接影响是，Julia的多重分派无法接受子类实例，如果参数标注为父类。

```julia
@oodef struct SuperC end
@oodef struct SubC <: SuperC end
function f(::SuperC) end
f(SuperC()) # ok
f(SubC())   # err
```


`@like(ootype)` 很好地解决了这一问题。类型标注为`@like(HasLength)`的函数参量可以接受`HasLength`的任意子类型。


```julia
@oodef struct SuperC end
@oodef struct SubC <: SuperC end
function f(::@like(SuperC)) end
f(SuperC()) # ok
f(SubC())   # ok!
```

### 例子，和零开销抽象

基于下面定义的接口`HasLength`，我们定义一个普通的Julia函数`a_regular_julia_function`：


```julia
@oodef struct HasLength
    function get_length end
end

function a_regular_julia_function(o :: @like(HasLength))
    function some_random_logic(i::Integer)
        (i * 3 + 5) ^ 2
    end
    some_random_logic(o.get_length())
end
```

现在，我们为`HasLength`实现一个子类`MyList`，作为`Vector`类型的包装：

```julia
@oodef struct MyList{T} <: HasLength
    inner :: Vector{T}

    function new(elts::T...)
        @mk begin
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

此外，我们指出，TyOOP的接口编程本身不导致动态分派。如果代码是静态分派的，抽象是零开销的。


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

P.S: 为接口增加默认方法可以实现著名的Mixin抽象。见[继承，多继承](@id inheritance_cn)中的`IPolygon`类型。

## 用`@typed_access`解决性能问题

因为编译器优化原因，使用Python风格的property会导致类型推导不够精准，降低性能。
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
