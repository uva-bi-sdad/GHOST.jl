push!(LOAD_PATH, joinpath("..", "src"))

using Documenter, OSSGH
using OSSGH: BaseUtils, Licenses

DocMeta.setdocmeta!(OSSGH,
                    :DocTestSetup,
                    :(using OSSGH;),
                    recursive = true)

makedocs(sitename = "OSSGH",
         modules = [OSSGH],
         pages = [
             "Home" => "index.md",
             "Manual" => "manual.md",
             "API" => "api.md"
         ]
)

deploydocs(repo = "github.com/uva-bi-sdad/OSSGH.jl.git",
           push_preview = true)