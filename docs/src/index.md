```@meta
CurrentModule = TyOOP
```

# TyOOP

[中文文档](index-cn.md)

[TyOOP](https://github.com/Suzhou-Tongyuan/TyOOP.jl) provides relatively complete object-oriented programming support for Julia. This is mainly based on CPython's object-oriented programming, and adapted for Julia.

The feature list is given below:

|  feature   | support  | notes |
|:----:  | :----:  | :----: |
| inheritance  | yes | upcasts/downcasts are not supported  |
| overloaded constructors and methods | yes | based on multiple dispatch |
| multiple inheritance | yes | MRO based on [C3](https://en.wikipedia.org/wiki/C3_linearization)|
| Python-style properties | yes | |
| default field values | yes | |
| generics  | yes |  |
| interfaces | yes | singleton struct types as base classes |
| modifiers  | no | just like Python |
| static class methods  | no | won't fix to avoid [type piracy](https://docs.julialang.org/en/v1/manual/style-guide/#Avoid-type-piracy) |
| metaclasses        | no | won't fix in favour of macros |

Quick start through [TyOOP Cheat Sheet](./cheat-sheet-en.md).

Note that we very much support the community idea "do not do OOP in Julia".

We make this guide **[Translating OOP into Idiomatic Julia](./how-to-translate-oop-into-julia.md)** to instruct users on how to translate OOP code into Julia, promising more concise, more extensible and more efficient code.

We even took the effort to design TyOOP as what it is now: the usage of OOP can be confined to the code of committed OOP users, and through interface programming, code of OOP exports APIs in normal Julia to avoid the proliferation of inappropriate code outside.

## OO type definition

TyOOP supports defining `class`es and `struct`s. A `class` definition starts with `@oodef mutable struct`, while a `struct` definition starts with `@oodef struct`.

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

As shown above, `function new(...)` is responsible for defining class/struct constructors.

We recommand using a `@mk begin ... end` block as the return value. In the block, you can specify zero or more `field_name = field_value` to initialize fields.

The behaviour when missing constructors:
1. if the type is a `class` (mutable struct), all fields are not initialized, as well as all base instances.
2. if the type is a `struct`, using Julia's default constructor.

Constructors can be overloaded.

For the struct types whose memory consumption is `0`, constructors can be omitted.

### Instance methods

instance methods should start with `function method_name(class_instance, ...)`. The instance variable is recommended to be named `self` or `this`.

The above code in both `MyClass` and `MyStruct` implement a method `f`. The method can be invoked using the syntax `instance.f()`.

```julia
@oodef mutable struct MyClass
    a :: Int
    
    # ... this part is omitted

    function f(self)
        self.a
    end
end
```

Instance methods support aribitrary Julia parameters, such as variadic parameters, keyword arguments, variadic keyword arguments, default positional arguments and default keyword arguments.

Besides, the instance methods support generic parameters, and can be overloaded.

(**P.S**) If you want to annotate the `self` parameter, it is recommended to use `self :: @like(MyClass)` instead of `self :: MyClass`. This is because the method might be invoked by the subclasses, while Julia does not support implicit conversions between types.

(**P.P.S**) What is `@like`? Given an OO type `Parent`, any subtype `Child` (also an OO type) inheriting `Parent` satisfies `Child <: @like(Parent)` in Julia, where `<:` is Julia's native subtyping operator. `Child <: Parent` can only be `false` in Julia.

### Default field values

Using this feature, when defining a field for classes/structs, if a default value is provided, then the initialization for this field can be missing in the `@mk` block.


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

Some points of the default field values:
1. there is no performance overhead in using default field values.
2. when a field has been explicitly initialized in the `@mk` block, the expression of the default field value won't be evaluated.
3. unlike `Base.@kwdef`, default field values cannot reference each other.

## Python-style constructors

The traditional OO languages such Python/C++/Java/C\# do not have native immutable types, so that the jobs of a constructor can be designed as follow:
1. creating a new instance `self` of the type.
2. invoking a constructor function to initialize the `self` instance. Side effects are introduced.

TyOOP can support such style for classes (`mutable struct`s), but it is not our best practice.

Example:

```julia
@oodef mutable struct MySubclass <: {MySuperclass1, MySuperclass2}
    field1
    function new()
        self = @mk
        # init fields
        self.field1 = 1
        # remember to return self
        return self
    end
```


## [Inheritances and multiple inheritances](@id inheritance)

Here is a simple example of class inheritance.

We firstly define two structs using `@oodef`:

```julia
@oodef struct A
    a :: Int
end

@oodef struct B
    b :: Int
end
```

Then, we define a type `C` to inherit `A` and `B`:

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

As can be seen, in the `@mk` block, we use `Base1(arg1, arg2), Base2(arg1, arg2)` to call the base classe constructors, which corresponds to `BaseType.__init__(self, arg1, arg2)` in Python.

A struct/class can inherit multiple base classes/structs. When name collision happens, we use C3 linearization algorithm to decide which one is to select. We use a variant of C3 to allow more flexible mixin uses.

The following example introduces mixin which is a common use of (multiple) inheritances:

We define a base class `IPolygon` which might have subclasses `Square`, `Rectangle`, `Triangle` or even general polygons. Despite the differences between these possible subclasses, a standard algorithm to compute perimeters is shared: sum up the lengths of all the edges.

```julia
using TyOOP

const Point = Tuple{Float64, Float64}
function distance(source::Point, destination::Point)
    sqrt(
        (destination[1] - source[1]) ^ 2 +
        (destination[2] - source[2]) ^ 2)
end

@oodef struct IPolygon
    # abstract method
    function get_edges end

    # mixin method
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

Leveraging the above `IPolygon`, we can define subclasses, reusing the `get_perimeter` method.

For instance, `Rectangle`：

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

    # for very special subclasses, we can overwrite
    # 'get_perimeter' to have a faster version:
    # function get_perimeter(self) ... end
end

rect = Rectangle(3.0, 2.0, (5.0, 2.0))
@assert rect.get_perimeter() == 10.0
```

P.S: OO types shall only inherit from OO types defined using TyOOP.

## Python-style properties

In Java, the getter functions `get_xxx` and setter functions `set_xxx` are used to encapsulate the implementation details and export more stable APIs.

The syntactic redundancies involved above can be adddressed by a syntatic sugar, which is named "properties" by many languages such as Python.

TyOOP supports so-called "properties", in the following apprach:

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

A more practical example is given below:

```julia
@oodef mutable struct Square
    side :: Float64
    function new(side::Number)
        @mk begin
            side = side # support auto cast
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

As can be seen, the side length of the square changes accordingly as the area gets changed.

## [Advanced feature: Abstract methods, and abstract properties](@id advanced_absmeths_and_absprops)

```julia
@oodef struct AbstractSizedContainer{ElementType}

    # abstract method
    function contains end


    # abstract property with only getter
    @property(length) do
        get
    end
end

# print not implemented methods (including properties)
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

## Advanced feature: Generics

Generics are pervasive, and in practice very common in data structures.

At [Advanced features：Abstract methods, and abstract properties](@ref advanced_absmeths_and_absprops), we have introduced `AbstractSizedContainer`. It has a generic type parameter `ElementType`.

```julia
@oodef struct AbstractSizedContainer{ElementType}
    # (self, ::ElementType) -> Bool
    function contains end
    @property(length) do
        get
    end
end
```

Although we do not use `ElementType` in the above example, it is useful if we need to specify a container's element type.

```julia
# containers of only numbers
@oodef struct AbstactNumberContainer{ElementType <: Number}
    ...
end

@oodef struct Optional{T}
    value :: Union{Nothing, Some{T}}
end
```

### Advanced feature: Explicit generic type parameters

The following code shows a special case where the constructor `new` cannot infer the generic type parameter `A` from the arguments:

```julia
@oodef struct MyGenType{A}
    a :: Int
    function new(a::Int)
        new{A}(a)
    end
end
```

In this case, we can explicitly specify the generic type parameters to construct instances:

```julia
my_gen_type = MyGenType{String}(1)
my_gen_type = MyGenType{Number}(1)
my_gen_type = MyGenType{Vector{Int}}(1)
```

## Advanced feature: Interfaces

TyOOP supports interface programming. Use `@oodef struct` to define a struct which has no fields, and add some abstract/mixin methods to it, in this way we achieve interface programming.

Despite the ease of connecting with the real business logic, interfaces also helps to specify proper constraints in your code.

### `@like(ootype)`

`@like` transforms a concrete OO type into a special abstract type.

```julia
julia> @like(HasLength)
Object{>:var"HasLength::trait"}
```

In Julia's type system, no concrete type can be inherited. A direct implication is that Julia's multiple dispatch does not accept a subtype instance if the parameter is annotated a base type. 

```julia
@oodef struct SuperC end
@oodef struct SubC <: SuperC end
function f(::SuperC) end
f(SuperC()) # ok
f(SubC())   # err
```

`@like(ootype)` addresses this. A function parameter `@like(HasLength)` accepts instances of any type that is a subtype of `HasLength`.

```julia
@oodef struct SuperC end
@oodef struct SubC <: SuperC end
function f(::@like(SuperC)) end
f(SuperC()) # ok
f(SubC())   # ok!
```

### Examples, and zero-cost abstraction

The following code based on the interface `HasLength` defines a regular Julia function `a_regular_julia_function`:

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

Now, we define a substruct `MyList` that inherits from `HasLength`, as the user wrapper of Julia's builtin `Vector` type:

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

We can see that only the OO type that implements `HasLength` is accepted by `a_regular_julia_function`.

Additionally, we point out that such interface abstraction itself does not introduce any dynamic dispatch. If your code contains only static dispatch, the abstraction is zero-cost.

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

P.S: Concrete methods defined in interfaces lead to a famous abstraction called Mixin. See `IPolygon` type at [Inheritances, and multiple inheritances](@id inheritance).

## Addressing performance issues via `@typed_access`

Because of the compiler optimization, using methods or Python-style properties might cause inaccurate type inference, and affect performance.

For possible performance issues, we provide `@typed_access`  to automatically optimize all `a.b` operations in Julia-compatible semantics.

```julia
@typed_access begin
    instance1.method(instance2.property)
end

# <=>

TyOOP.getproperty_typed(instance1, Val(:method))(
    TyOOP.getproperty_typed(instance, Val(:property))
)
```

`@typed_access` slows down dynamic calls，but removes overheads of static calls。For `a.b`，if the type of `a` is successfully inferred, then `@typed_access a.b` is strictly faster than `a.b`.
