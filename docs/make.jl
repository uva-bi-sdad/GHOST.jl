push!(LOAD_PATH, joinpath("..", "src"))

using Documenter, OSSGH
using OSSGH
using OSSGH: BaseUtils, Licenses

ENV["POSTGIS_HOST"] = get(ENV, "POSTGIS_HOST", "host.docker.internal")
ENV["POSTGIS_PORT"] = get(ENV, "POSTGIS_PORT", "5432")
ENV["GITHUB_TOKEN"] = get(ENV, "GITHUB_TOKEN", "")

DocMeta.setdocmeta!(OSSGH,
                    :DocTestSetup,
                    :(using OSSGH, DataFrames, Printf;
                      opt = Opt("Nosferican",
                                ENV["GITHUB_TOKEN"],
                                host = ENV["POSTGIS_HOST"],
                                port = parse(Int, ENV["POSTGIS_PORT"]));),
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