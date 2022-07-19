using ObjectOriented
using Documenter

DocMeta.setdocmeta!(ObjectOriented, :DocTestSetup, :(using ObjectOriented); recursive=true)

makedocs(;
    modules=[ObjectOriented],
    authors="thautwarm <twshere@outlook.com> and contributors",
    repo="https://github.com/Suzhou-Tongyuan/ObjectOriented.jl/blob/{commit}{path}#{line}",
    sitename="ObjectOriented.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://Suzhou-Tongyuan.github.io/ObjectOriented.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Cheat Sheet" => "cheat-sheet-en.md",
        # "index-cn.md",
        # "cheat-sheet-cn.md",
        "Translating OOP into Idiomatic Julia" => "how-to-translate-oop-into-julia.md"
    ],
)

deploydocs(;
    repo="github.com/Suzhou-Tongyuan/ObjectOriented.jl",
    devbranch="main",
)
