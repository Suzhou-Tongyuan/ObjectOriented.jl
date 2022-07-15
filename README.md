# ObjectOriented

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://Suzhou-Tongyuan.github.io/ObjectOriented.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://Suzhou-Tongyuan.github.io/ObjectOriented.jl/dev/)
[![Build Status](https://github.com/Suzhou-Tongyuan/ObjectOriented.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Suzhou-Tongyuan/ObjectOriented.jl/actions/workflows/CI.yml?query=branch%3Amain)

[ObjectOriented](https://github.com/thautwarm/ObjectOriented.jl) is a mechanical OOP programming library for Julia. The design is mainly based on CPython OOP but adapted for Julia.


The supported features:

- multiple inheritances
- using dot operators to access members
- default field values
- overloaded constructors and methods
- Python-style properties (getters and setters)
- generics for the OOP system
- interfaces

Check out our [documentation](https://Suzhou-Tongyuan.github.io/ObjectOriented.jl/dev/).

We recommend you to read [How to Translate OOP into Idiomatic Julia](https://suzhou-tongyuan.github.io/ObjectOriented.jl/dev/how-to-translate-oop-into-julia) before using this package. If you understand your complaints about Julia's lack of OOP come from your refutation of the Julia coding style, feel free to use this.

For people who want to use this package in a more Julian way, you can avoid defining methods (and Python-style properties) with `@oodef`.

## Preview

```julia
@oodef mutable struct MyClass <: MySuperClass
    a::Int
    b::Int

    function new(a::Integer, b::Integer)
        self = @mk
        self.a = a
        self.b = b
        return self
    end

    function compute_a_plus_b(self)
        self.a + self.b
    end
end

julia> inst = MyClass(1, 2)
julia> inst.compute_a_plus_b()
3
```

A more concise rewrite using `@mk` is:


```julia
@oodef mutable struct MyClass <: MySuperClass
    a::Int
    b::Int

    function new(a::Integer, b::Integer)
        @mk begin
            a = a
            b = b
        end
    end

    function compute_a_plus_b(self)
        self.a + self.b
    end
end

julia> inst = MyClass(1, 2)
julia> inst.compute_a_plus_b()
3
```

## Hints For Professional Julia Programmers

As the dot method (`self.method()`) is purely a syntactic sugar thing, using the idiomatic Julia code like `method(self)` is usually better.

You can just avoid defining dot methods:

```julia
@oodef struct MyType
    field1::Int
    field2::Int
    function new(a, b)
        @mk begin
            field1=a
            field2=b
        end
    end

    #= not Julian:
    function some_func(self)
       return self.field1 + self.field2
    end
    =#
end

# Julian way:
function some_func(self :: @like(MyType)) # @like(...) accepts subtypes
    self.field1 + self.field2
end

@oodef struct MyDerivedType <: MyType
    c::Int
    function new(a, b, c)
        @mk begin
            MyType(a, b)
            c = c
        end
    end
end

some_func(MyType(1, 2)) # 3
some_func(MyDerivedType(1, 2, 3)) # 3
```
