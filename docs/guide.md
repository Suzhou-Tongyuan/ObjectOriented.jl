# TyOOP

TyOOP为Julia提供一套完整的面向对象抽象，其机制主要取自CPython的面向对象实现。

其功能一览如下：

|  功能名   | 支持  | 注释 |
|:----:  | :----:  | :----: |
| 点操作符 | 是 | |
| 继承  | 是 | 基类、子类不能直接转换 |
| 多继承 | 是 | 是，属性resolution使用Python C3算法 | 
| 泛型  | 是 |  |
| 接口 | 是 | 使用空结构体类型的基类 |
| 构造器和实例方法重载 | 是 | 多重分派 |
| Python风格 properties | 是 | |
| 权限封装(modifiers)  | 否 | 同Python |
| 类静态方法  | 否 | 与Julia理念严重冲突，且极易替代 |
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

### 构造器

上述代码中，`function new(...)`用于定义构造器。
构造器的返回值应当使用`@construct begin ... end`构造一个当前类型的实例，其中，`begin`语句块中使用`字段名=值`初始化字段。

缺省构造器的行为：
- 当类型为`class`，所有字段未初始化。
- 当类型为`struct`，且存在字段，使用Julia生成的构造器(`dataclass`)

构造器可以被重载。对于空间占用为0的结构体(单例类型)，构造器可以省略。

### 实例方法

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

### 继承，多继承

下面是一个简单的继承例子。多继承是允许的。

```julia
@oodef struct A
    a :: Int
end

@oodef struct B
    b :: Int
end

@oodef struct C <: {A, B}
    function new(a::Int, b::Int)
        @construct begin
            @base(A) = A(a)
            @base(B) = B(b)
        end
    end
end

c = C(1, 2)
@assert c.a === 1
@assert c.b === 2
```

当多个基类出现重名属性时，使用

下面这个例子给了一种常见的继承应用场景。

```julia
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

@oodef struct Rectangle <: IPolygon
    height :: Float64
    width :: Float64
    center :: Point

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

    # 可以重写 get_perimeter 获得更快的求周长方法
    # function get_perimeter()
end
```

### Python风格的properties