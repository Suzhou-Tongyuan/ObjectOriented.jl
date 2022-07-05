# TyOOP

[TyOOP](https://github.com/thautwarm/TyOOP.jl) is a complete and mechanical OOP programming library for Julia. The design is mainly based on CPython OOP but adapted for Julia, intentionally 
for Python users.

The supported features:Python
- using dot operators to access members from the current class or base classes.
- multiple inheritances
- overloaded constructors and methods
- Python-style properties (getters and setters)
- default field values
- generic support to the OOP System
- interfaces

## A Simple Example

```julia
@oodef mutable struct MyClass <: MySuperClass
    a :: Int
    b :: Int

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
    a :: Int
    b :: Int

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
