# Translating OOP into Idiomatic Julia

Multiple dispatch used by Julia gives a novel solution to the [expression problem](https://en.wikipedia.org/wiki/Expression_problem), while the so-called object-oriented programming has a different answer that is much more popular.

Although we'd admit that there are some essential differences between OOP and multiple dispatch under the hood, they are not that different. In fact, Julia's multiple dispatch definitely steps further and can fully express OOP, although certain translation (very rare) is so far never efficient (I mean, fast in execution time).

This article aims at telling people how to translate serious OOP code into idiomatic Julia. The translation is divided into the following sections:

- Julia representation of constructors
- Julia representation of methods
- Julia representation of inheritance
- Julia representation of interfaces

## Julia representation of constructors

In Python, we might simply write a class as follow.

```python
class MyClass:
    def __init__(self, a):
        self.a = a
        self.b = a + a

MyClass(1)
```

Python encapsulates instantiation and the instance initialization into a single call `MyClass(1)`, but if we dig a little deeper, we will know that the construction of a Python object works like this:

```python
inst = MyClass.__new__(MyClass, 1)
if isinstance(inst, MyClass):
    MyClass.__init__(inst, 1)
return inst
```

We have found a fresh Julia user who comes from the OOP world can be anxious about the constructor. In Julia, a struct provides a default constructor which takes arguments in order of the class fields. This asks Julia users to create an instance (like `__new__()`) manually, but OOP guys would rather only create instance initialization function (like `__init__()`) themselves.

```julia
struct MyClass
    a
    b
end

b = a + a
MyClass(a, b)
```

However, achieving what OOP guys need is convenient and even mechanical. "Convenient" means Julia can do the same thing in a way less verbose than others, and "mechanical" means this is a general solution to the problem, and the problem is well-studied in the used mechanism.

We post the solution as follow. For readability, the code is simplified and the functionality is incomplete in corner cases.

The solution has 2 parts, the first one is the library code which is not very readable, but it is not responsible for users to implement; the second part is the user code, it is readable and concise, exactly like what in Python.

### [Library code](@id lib_constructor)

```julia
## `new` and `init` can be overloaded for different classes
@generated function default_constructor(::Type{Cls}) where Cls
    Expr(:new, Cls)
end

function new(cls, args...; kwargs...)
    # call default constructor without field initialization
    return default_constructor(cls)
end

function init(self, args...; kwargs...)
    nothing
end

abstract type OO end

function (::Type{Cls})(args...; kwargs...) where Cls <: OO
    inst = new(Cls, args...; kwargs...)
    if inst isa Cls
        init(inst, args...; kwargs...)
    end
    return inst
end
```

### User code

```julia
mutable struct MyClass <: OO
    a
    b
end

function init(self::MyClass, a)
    self.a = a
    self.b = a + a
end

MyClass(1)
```

If we mark the functions `new`, `init` or `(::Type{Cls})` with `@inline`, the code becomes as efficient as in C/C++.

However, Julia does not adopt this solution. There are many reasons, but the key one is that Julia has native support for immutability. Mutable classes can be created without initializing fields but modified later, while immutable structs never support this. 

```julia
struct Data
    a::Int
end
data = Data(1)
data.a = 2

ERROR: setfield!: immutable struct of type Data cannot be changed
```

The old and popular approach to object construction, like Python's `__init__`, works in the old world, but using it for a language providing new features (like immutability) is not deemed a good idea. The old solution can be provided as a library, but it discourages the use of the good features such as immutability.

ObjectOriented.jl provides the `new` function and `@mk` macro to address above issue. Using `new` and `@mk`, your code is slightly more concise than in Python, and works for both mutable structs and immutable structs.

## Julia representation of methods

In Python, we can define methods for a class so that its instance can call the method with `instance.method()`.

```python
class MyClass2:
    def __init__(self, x):
        self.x = x

    def double(self):
        return self.x * 2

MyClass2(1).double() # => 2
```

However, in Julia, field accessing is using dot operators, while method accessing is not related to instances or even types. Methods are defined juxtaposing the structs.

```julia
struct MyClass2
    a::Int
end

double(self) = self.a * 2

double(MyClass2(1)) # => 2
```

The translation of dot methods is maybe the most direct translation in this article. This is because all OOP languages do the same thing as Julia under the hood.

If we DO want to support dot methods in Julia, just set up the same mechanism used by Python or any other OOP language that support bound methods (examples: C\#, Python; counter examples: Java, JavaScript).


```julia
struct BoundMethod{Func, Self}
    func::Func
    self::Self
end

function (boundmethod::BoundMethod{Func, Self})(args...; kwargs...) where {Func, Self}
    boundmethod.func(boundmethod.self, args...; kwargs...)
end

Base.getproperty(self::MyClass2, name::Symbol) =
    if name === :double
        BoundMethod(double, self)
    else
        Base.getfield(self, name)
    end

MyClass2(1).double() # 2
```

Supporting dot methods in Julia is NOT RECOMMANDED due to the poor IDE support and other conventions like "dot operators access fields".

Besides, strongly coupling methods with classes is found not a general solution. A real-world counter example is operator overloading, where Julia's multiple dispatch is the-state-of-the-art solution to the problem. The infrastructure part of deep-learning frameworks requires facilities similar to multiple dispatch, where an evidence can be found from [this discussion](https://news.ycombinator.com/item?id=29354474).

You probably don't know an interesting fact: dot methods are not really a component of OOP, it's just a historical idiom of many OOP languages.

From the perspective of programming languages, dot methods are so-called runtime single dispatch, and I've recently found that the popularity of runtime single dispatch has led to a general inability of identifying problems or requirements that are essentially multiple-dispatched. Such fact can be usually observed from the user API functions made by programmers from classic OOP languages.

## Julia representation of inheritance

Many smart programmers from the OOP world have already found the technique described above, but it seems that many of them give up in handling inheritance.

However, a general solution to inheritance in Julia is still easy until we need syntactic sugar support.

In Python, a class can inherit from other classes, and the child class can access the parents' fields and methods, or override some of the methods. We give the following example:

```python
class A:
    def __init__(self):
        self.x = 1

class B:
    def __init__(self, *args):
        self.args = args

    def print_args(self):
        print(self.args)

class AB(A, B):
    def __init__(self, *args):
        A.__init__(self)
        B.__init__(self, *args)

ab = AB(1, 2, 3)
ab.x # 1
ab.print_args() # (1, 2, 3)
```

To implement inheritance, we need basic understanding of what it is.

Inheritance in different OOP languages have different underlying implementations. Many statically-typed languages such as C++/Java/C\# implement inheritance with composition, where a class instance implicitly holds base class instances (`sizeof` can be 0) as fields. However, dynamic languages such as Python provide inheritance similar to "mixin", where base classes are (usually) only related to reusing methods, and the instance is created only by the derived class's `__new__` so that instances (usually) do not hold the base class instances. 

The major difference between these two implementations in the userland, other than performance, is the capability to have more than one same-name fields in different base classes or the derived class. Composition-based inheritance allows more than one same-name fields from different classes, but mixin-like inheritance implies the same name always references the the same member.

Efficient encoding of inheritance in Julia needs composition. This is because the mixin-like inheritance shares the same data (and its memory layout) for all base classes, then the instance have to be something like a dictionary, which is not preferred.

The core idea of composition-based inheritance is very simple. Suppose our class inherits a base class `BaseCls`, which has a field `base_field`. As the base class instance is stored in a field of the derived class instance, accessing `base_field` is no more than firstly access the base class instance and use it to access the `base_field` normally.

Hence, the aforementioned Python code can be translated into:

```julia
mutable struct A <: OO
    x::Int
end

function init(self::A) 
    self.x = 1
end

mutable struct B <: OO
    args
end

function init(self::B, args...)
    self.args = args
end

print_args(b) = println(b.args)

mutable struct AB <: OO
    _base_a::A
    _base_b::B
end

function init(self::AB, args...)
    self._base_a = A()   # A.__init__(self)
    self._base_b = B(args...) # B.__init__(self, args...)
end

Base.getproperty(self::AB, name::Symbol) =
    if name === :x
        self._base_a.x
    elseif name === :args
        self._base_b.args
    else
        Base.getfield(self, name)
    end

ab = AB(1, 2, 3)
ab.x # 1
print_args(ab) # (1, 2, 3)
```

Note that methods applicable to base classes (e.g., `print_args`) also work for derived classes.

However, the issues is that users have to manually create `Base.getproperty`, which is definitely not acceptable. Fortunately, the above code does suggest a general and efficient solution: when defining a class, we statically resolve which field name is referencing which field from which class, and finally generate a `Base.getproperty` (and `Base.setproperty!`).

Julia allows this with runtime code generation (staging), providing us a zero-cost implementation.

Think that we use a special struct `Inherit{T}` to distinguish normal fields from the fields that store base class instances.

```julia
struct Inherit{Cls}
    base_inst::Cls
end

mutable struct BaseCls <: OO
    base_field::Int
end

mutable struct DerivedCls <: OO
    _base::Inherit{BaseCls}
end
```

In the following subsection, given `x::DerivedCls`, we make `x.base_field` retrieves `x._base.base_inst.base_field`.

### [Library code](@ref lib_inheritance)

There is no need to fully understand the details, and the code is provided for copy-paste.

```julia
struct Inherit{Cls}
    base_inst::Cls
end

Base.@pure function _pathed_fieldnames(@nospecialize(t))
    t <: OO || error("Not an OO type")
    fts = fieldtypes(t)
    fns = fieldnames(t)
    pathed_names = Tuple{Tuple, Symbol}[]
    for i in eachindex(fns, fts)
        ft = fts[i]
        if ft <: Inherit && ft isa DataType # concrete
            base_t = ft.parameters[1]
            for (path, n) in _pathed_fieldnames(base_t)
                if !startswith(string(n), "_")
                    push!(
                        pathed_names,
                        ((i, 1, path...), n))
                end
            end
        else
            # make '_xxx' private
            push!(pathed_names, ((i, ), fns[i]))
        end
    end
    Tuple(pathed_names)
end

Base.@pure function _fieldnames(@nospecialize(t))
    Tuple(unique!([x[2] for x in _pathed_fieldnames(t)]))
end

@inline @generated function unroll_select(f, orelse, ::Val{tuple}, x, args...) where tuple
    expr = Expr(:block)
    foldr(tuple, init=:(return orelse(x))) do l, r
        Expr(:if,
            :(x === $(QuoteNode(l))),
            :(return f($(Val(l)), args...)), r)
    end
end


@inline @generated function _getproperty(self::T, ::Val{fieldname}) where {T <: OO, fieldname}
    pathed_names = _pathed_fieldnames(T)
    for (path, name) in pathed_names
        if name === fieldname
            return foldl(path, init=:self) do l, r
                :($getfield($l, $r))
            end
        end
    end
    return :($error("type " * string(T) * " has no field " * string(fieldname)))
end

function _do_with_field_found(typed_name::Val, self)
    _getproperty(self, typed_name)
end

@inline function Base.getproperty(self::T, name::Symbol) where T <: OO
    function _do_with_field_unfound(name::Symbol)
        error("type $(string(T)) has no field $(string(unknown_name))")
    end
    unroll_select(
        _do_with_field_found,
        _do_with_field_unfound,
        Val(_fieldnames(T)),
        name,
        self,
    )     
end
```

### User code

Using the library code above, we can avoid manual implementation of `Base.getproperty`.

```julia
mutable struct A <: OO
    x::Int
end

function init(self::A) 
    self.x = 1
end

mutable struct B <: OO
    args
end

function init(self::B, args...)
    self.args = args
end

print_args(b) = println(b.args)

mutable struct AB <: OO
    _base_a::Inherit{A}
    _base_b::Inherit{B}
end

function init(self::AB, args...)
    self._base_a = Inherit(A())   # A.__init__(self)
    self._base_b = Inherit(B(args...)) # B.__init__(self, args...)
end


ab = AB(1, 2, 3)
ab.x # 1
print_args(ab) # (1, 2, 3)
```

## Julia representation of interfaces

OOP uses interfaces to specify valid behaviours of an open family of classes. It helps the following programming requirements:

1. hiding implementation details about concrete classes
2. reusing the functions for multiple classes
3. specifying constraints of input and output

Recently, many OOP languages get started supporting default method implementations for interfaces, so interfaces are now not that different from multi-inheritable, zero-field abstract classes.

Interfaces in Python are not very standard, but they do work under the help of Python's mature IDEs.

Here is an example of using interfaces in Python:

```python
class MyInterface:
    def abs_func(self, arg):
        raise NotImplementedError

    def mixin_func(self, arg):
        return "mixin " + self.abs_func(arg)

class Cls1(MyInterface):
    def abs_func(self, arg):
        return "cls1"

class Cls2(MyInterface):
    def abs_func(self, arg):
        return "cls2"

# Use interfaces!
def func_reusing_for_multi_classes(self: MyInterface, arg):
    return self.mixin_func(arg)

func_reusing_for_multi_classes(Cls2(), "xxx") # "mixin cls2"
```

Such code can be translated into Julia using `abstract type`:

```julia
abstract type MyInterface end
abs_func(self::MyInterface, arg) =
    error("'abs_func' is not defined for $(typeof(self)).")

mixin_func(self::MyInterface, arg) =
    "mixin " * abs_func(self, arg)

struct Cls1 <: MyInterface end
struct Cls2 <: MyInterface end

abs_func(self::Cls1, arg) = "cls1"
abs_func(self::Cls2, arg) = "cls2"

# Use interfaces!
func_reusing_for_multi_classes(self::MyInterface, arg) =
    mixin_func(self, arg)

func_reusing_for_multi_classes(Cls2(), "xxx") # "mixin cls2"
```

As can be seen above, the code in Julia is slightly more concise than that in Python.

## Conclusions

OOP features, such as constructors, methods, inheritance, and interfaces, have corresponding translation in Julia.

For most of tasks involving OOP, the translation is straightforward and even more concise than the original code.

However, we'd still admit such translation has limitations, while the limitation is never about missing language features.

A notable limitation is about the performance of the runtime polymorphisms. OOP's polymorphism is vtable-based runtime polymorphism, which makes OOP code run pretty fast when handling a container of abstract typed elements. Julia performs worse in this case when you translate OOP code into Julia, to which there is no general solution.

Another important limitation is about IDE support or code introspection. I'm always thinking that people are not really complaining about Julia's lack of OOP support, but the lack of dot operators, I mean, some language facility to organize and search definitions.

For instance, if I know a class is iterable, I'd like to know the available methods (such as `iterate`) or fields by simply typing `something.<TAB>`. So far we have to browse the documentation, otherwise we cannot even find out the methods intentionally defined for some abstract type.

(Possibly off-topic) I don't really want to be a boring guy who talks about how much better a FP language could be, but if possible we could learn about API organization from Erlang or Haskell. If operations for iterables are registered in a module `Iterables`, and `Iterables.<TAB>` shows `iterate` in the completion list for me, I'd be more satisfied.
