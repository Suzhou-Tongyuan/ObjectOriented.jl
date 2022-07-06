using TyOOP
using Documenter

DocMeta.setdocmeta!(TyOOP, :DocTestSetup, :(using TyOOP); recursive=true)

makedocs(;
    modules=[TyOOP],
    authors="thautwarm <twshere@outlook.com> and contributors",
    repo="https://github.com/Suzhou-Tongyuan/TyOOP.jl/blob/{commit}{path}#{line}",
    sitename="TyOOP.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://Suzhou-Tongyuan.github.io/TyOOP.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Cheat Sheet" => "cheat-sheet-en.md",
        "index-cn.md",
        "cheat-sheet-cn.md"
    ],
)

deploydocs(;
    repo="github.com/Suzhou-Tongyuan/TyOOP.jl",
    devbranch="main",
)
