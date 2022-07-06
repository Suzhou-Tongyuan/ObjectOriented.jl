## Translating OOP into Idiomatic Julia

Multiple dispatch used by Julia gives a novel solution to the [expression problem](https://en.wikipedia.org/wiki/Expression_problem), while the so-called object-oriented programming has a distinct but much more popular answer.

Although we'd admit that there are some essential differences between OOP and multiple dispatch under the hood, they are not that different. In fact, Julia's multiple dispatch definitely steps further and can fully express OOP, although certain translation is so far never efficient.

This article aims at telling people how to translate serious OOP code into idiomatic Julia. The translation is divided into the following sections:

- Julian representation of classes and constructors
- Julian representation of class methods
- Julian representation of inheritances
- Julian representation of multiple inheritances and method resolution
- Julian representation of interfaces
- Julian representation of traits

After going through above details, we'll finally raise the point that Julia fully expresses OOP except

1. an efficient implementation of modular dynamic dispatch
2. implicit upcasts
3. code constraints

We are pragmatic. The disadvantages of multiple dispatch about IDE support and user mental model will also be included.

(under construction)
