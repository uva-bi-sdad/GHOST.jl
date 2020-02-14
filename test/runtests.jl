using Test, Documenter, OSSGH
using OSSGH
# using OSSGH.BaseUtils: graphql, gh_errors, handle_errors
ENV["POSTGIS_HOST"] = get(ENV, "POSTGIS_HOST", "host.docker.internal")
ENV["POSTGIS_PORT"] = get(ENV, "POSTGIS_PORT", "5432")
ENV["GITHUB_TOKEN"] = get(ENV, "GITHUB_TOKEN", "")

opt = Opt("Nosferican",
          ENV["GITHUB_TOKEN"],
          host = ENV["POSTGIS_HOST"],
          port = parse(Int, ENV["POSTGIS_PORT"]))

@testset "Setup" begin
    execute(opt.conn, "DROP SCHEMA IF EXISTS $(opt.schema) CASCADE;")
    setup(opt)
    @test execute(opt.conn,
                  "SELECT COUNT(*) > 0 AS ok FROM information_schema.schemata WHERE schema_name = '$(opt.schema)';") |>
        rowtable |>
        (data -> data[1].ok)
end
@testset "Licenses" begin
    licenses(opt)
    @test execute(opt.conn,
                  "SELECT COUNT(*) = 29 AS ok FROM $(opt.schema).licenses;") |>
        rowtable |>
        (data -> data[1].ok)
end
@testset "Search" begin
    data = execute(opt.conn,
                   "SELECT spdx FROM $(opt.schema).licenses ORDER BY spdx DESC LIMIT 1;") |>
        rowtable;
    foreach(row -> search(opt, row...), data)
    @test execute(opt.conn,
                  "SELECT COUNT(*) > 0 AS ok FROM $(opt.schema).licenses;") |>
        rowtable |>
        (data -> data[1].ok)
end
@testset "Repos" begin
    data = execute(opt.conn,
                   "SELECT spdx, created_query FROM $(opt.schema).spdx_queries ORDER BY spdx ASC, created_query ASC;") |>
        rowtable
    foreach(row -> repos(opt, row...), data)
    @test execute(opt.conn,
                  "SELECT COUNT(*) = 0 AS ok FROM $(opt.schema).spdx_queries WHERE status != 'Done';") |>
        rowtable |>
        (data -> data[1].ok)
end
@testset "Commits" begin
    data = execute(opt.conn, "SELECT slug FROM $(opt.schema).repos ORDER BY slug ASC LIMIT 1;") |>
        rowtable
    foreach(row -> commits(opt, row...), data)
    @test execute(opt.conn,
                  "SELECT COUNT(*) = 1 AS ok FROM $(opt.schema).repos WHERE status = 'Done';") |>
          rowtable |>
          (data -> data[1].ok)
    execute(opt.conn, "UPDATE $(opt.schema).repos SET status = 'Initiated'";)
    execute(opt.conn,
            """DELETE FROM $(opt.schema).commits
               WHERE committed_date >=
                 (SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY committed_date ASC) AS median
               FROM $(opt.schema).commits);
            """)
    foreach(row -> commits(opt, row...), data)
    @test execute(opt.conn,
                  "SELECT COUNT(*) = 1 AS ok FROM $(opt.schema).repos WHERE status = 'Done';",
                  not_null = true) |>
        rowtable |>
        (data -> data[1].ok)
end
@testset "Documentation" begin
    using Documenter, OSSGH
    using OSSGH: BaseUtils, Licenses, Search, Repos, Commits

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
             ],
             source = joinpath("..", "docs", "src"),
             build = joinpath("..", "docs", "build"),
             )
    @test true
end
