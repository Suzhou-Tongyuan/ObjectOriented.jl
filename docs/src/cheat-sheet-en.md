## TyOOP cheat sheet

TyOOP has provided relatively complete object-oriented programming support for Julia. It supports multiple inheritances, dot-operator access to members, Python-style properties and interface proramming.

### 1. Type definition

Define immutable OO structs:

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

`new`is the constructor. Constructs and methods can be overloaded.

A `@mk` block creates an instance for the current struct/class. Inside the block, an assignment statement `a = b` initializes the field `a` with the expression `b`; a call statement like `BaseType(arg1, arg2)` calls the constructor of the base class/struct `BaseType`.

Defining OO classes (mutable structs):

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

#### Default field values

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

**CAUTION**:

```julia
Snake <: Animal # false
Snake("xxx") isa Animal # false
```

Note that Julia's native type system does not understand the subtyping relationship between two oo classes! See [Interface-based polymorphism](@ref interface_polymorphism_cn) for more details.

Use the following methods to test inheritance relationship:

```julia
issubclass(Snake, Animal) # true
isinstance(Snake("xxx"), Animal) # true
Snake("xxx") isa @like(Animal) # true
```

### 4. Python-style properties

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

### 5. Interfaces

An interface in TyOOP means an OO struct type which satisfies `sizeof(interface) == 0`.

Interface constructors are auto-generated, but custom constructors are allowed.

The following `HasLength` is an interface.

```julia
@oodef struct HasLength
    @property(len) do
        get  # abstract getter property
    end
end

@oodef struct Fillable
    function fill! end # an empty function means abstract method

    # define an abstract property  to set all values
    @property(allvalue) do
        set
    end
end

@oodef struct MyVector{T} <: {HasLength, Fillable}  # multiple inheritance
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

`check_abstract(MyVector)` is not empty. This means `MyVector` is abstract (more accurately, shall not be instantiated). Otherwise, implementing `len`, `fill!`和`allvalue` is required.



```julia
@oodef struct MyVector{T} <: {HasLength, Fillable}  # multiple inheritance
    xs :: Vector{T}
    function new(xs::Vector{T})
        @mk begin
            xs = xs
        end
    end

    # add the following definitions to 
    # implement `HasLength` and `Fillable`
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

In addition, the most important reason for interfaces is the interface-based polymorphism. See [Interface-based polymorphism](@ref interface_polymorphism_cn).


### 6. 多继承

MRO (Method resolution order) is using Python's C3 algorithm, so the behaviour is mostly identical to Python. The major difference is that the order of inheriting mixin classes is less strict.

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
            A() # can omit. A is interface.
            B() # can omit. B is interface.
            C() # cannot omit. C is class (mutable struct).
            # you can also write them in one line:
            # A(), B(), C()
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

### 7. [Interface-based polymorphism](@id interface_polymorphism_cn)


The following example shows an inproper use of the base class (`A`):

```julia
@oodef struct A end
@oodef struct B <: A end
myapi(x :: A) = println("do something!")

myapi(A())
# do something!

myapi(B())
# ERROR: MethodError: no method matching myapi(::B)
```

Remember that Julia's type system does not understand the subtyping relationship between two OO classes!

If you expect `myapi`  to accept `A` or `A`'s subtypes, you should do this:

```julia
myapi(x :: @like(A)) = println("do something!")

myapi(B())
# do something!

myapi([])
# ERROR: MethodError: no method matching myapi(::Vector{Any})
```


### 8. A machine learning example

In the following code, we implement a machine learning model trained using least squares and make it support the ScikitLearn interface (ScikitLearnBase.jl) in Julia. With the following code, users can call this model as if it were a normal ScikitLearn.jl model, and can use this model in the MLJ machine learning framework, regardless of whether the model is implemented by object-oriented features or multiple dispatch.

```julia
using TyOOP

@oodef struct AbstractMLModel{X, Y}
    function fit! end
    function predict end
end

using LsqFit

@oodef mutable struct LsqModel{M<:Function} <: AbstractMLModel{Vector{Float64},Vector{Float64}}
    model :: M  # a function to represent the model's formula
    param :: Vector{Float64}

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

# the example comes from https://github.com/JuliaNLSolvers/LsqFit.jl

@. model(x, p) = p[1] * exp(-x * p[2])
clf = LsqModel(model, [0.5, 0.5])
ptrue = [1.0, 2.0]
xdata = collect(range(0, stop = 10, length = 20));
ydata = collect(model(xdata, ptrue) + 0.01 * randn(length(xdata)));

clf.fit!(xdata, ydata) # train
clf.predict(xdata)     # predict
clf.param              # inspect model parameters

# ScikitLearnBase provides us two interface functions 'fit!' and 'predict'.
# Now, we connect the TyOOP interface with Julia's idiomatic interface
# via '@like(...)'.

using ScikitLearnBase
ScikitLearnBase.is_classifier(::@like(AbstractMLModel)) = true
ScikitLearnBase.fit!(clf::@like(AbstractMLModel{X, Y}), x::X, y::Y) where {X, Y} = clf.fit!(x, y)
ScikitLearnBase.predict(clf::@like(AbstractMLModel{X}), x::X) where X = clf.predict(x)

ScikitLearnBase.fit!(clf, xdata, ydata)
ScikitLearnBase.predict(clf, xdata)
```

### 9. Performance issues

Code generated by TyOOP does not introduce any overhead, but recursions of dot operations (`Base.getproperty(...)`) do have some issues concerning type inference (e.g., [this example](https://discourse.julialang.org/t/type-inference-problem-with-getproperty/54585/2?u=thautwarm)). Although in most cases, the code produced by TyOOP is very efficient, the return type might suddenly becomes `Any` or some `Union` type.


This might cause performance issues, but only in enumerable cases that have been well understood:

1. Using Python-style properties
2. Visiting another member in methods, the member will recursively perform dot operations (`Base.getproperty`).

The solution is easy: use `@typed_access` to wrap a block of code which might suffer from above issues.

```julia
@typed_access my_instance.method()
@typed_access my_instance.property
```

**CAUTION**: please make sure that the type of the above `my_instance` is inferred when using `@typed_access`. Using `@typed_acccess` in dynamic code will damage your performance.
