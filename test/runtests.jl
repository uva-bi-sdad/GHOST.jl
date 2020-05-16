# run(`ijob -A biocomplexity -p bii -t 0-04:00:00 -c 30 --mem=256GB`)
# julia --proj

filter!(isequal(joinpath(homedir(), ".julia")), DEPOT_PATH)
# using Revise
# using Distributed
# addprocs(parse(Int, ENV["SLURM_CPUS_PER_TASK"]) - 1, exeflags = `--proj`)
# @everywhere using Revise
using LibPQ: Connection, execute, rowtable
conn = Connection("""
                  host = $(get(ENV, "PGHOST", ""))
                  dbname = sdad
                  user = $(get(ENV, "DB_USR", ""))
                  password = $(get(ENV, "DB_PWD", ""))
                  """);
using GHOSS

pats = execute(conn, "SELECT * FROM gh.pat ORDER BY login;", not_null = true) |>
    rowtable |>
    (obj -> [ GHOSS.GitHubPersonalAccessToken(row.login, row.pat) for row in obj ] )

setup_parallel(pats)

spdxs = execute(conn,
                """
                SELECT LOWER(spdx) AS spdx
                FROM gh_2007_2019.licenses
                WHERE LOWER(spdx) NOT IN (
                    SELECT LOWER(spdx) AS spdx
                    FROM gh_2007_2019.queries
                    WHERE UPPER(created) = '2020-01-01'
                )
                ;
                """,
                not_null = true) |>
    (obj -> getproperty.(obj, :spdx))

time_start = GHOSS.now(GHOSS.utc_tz)
foreach(spdx -> queries(conn, spdx), spdxs)
time_finished = GHOSS.now(GHOSS.utc_tz)
GHOSS.Dates.canonicalize(GHOSS.Dates.CompoundPeriod(time_finished - time_start))

# @testset "Setup" begin
#     execute(opt.conn, "DROP SCHEMA IF EXISTS $(opt.schema) CASCADE;")
#     setup(opt)
#     @test execute(opt.conn,
#                   "SELECT COUNT(*) > 0 AS ok FROM information_schema.schemata WHERE schema_name = '$(opt.schema)';") |>
#         rowtable |>
#         (data -> data[1].ok)
# end
# @testset "Licenses" begin
#     licenses(opt)
#     @test execute(opt.conn,
#                   "SELECT COUNT(*) = 29 AS ok FROM $(opt.schema).licenses;") |>
#         rowtable |>
#         (data -> data[1].ok)
# end
# @testset "Search" begin
#     data = execute(opt.conn,
#                    "SELECT spdx FROM $(opt.schema).licenses ORDER BY spdx DESC LIMIT 1;") |>
#         rowtable;
#     foreach(row -> search(opt, row...), data)
#     @test execute(opt.conn,
#                   "SELECT COUNT(*) > 0 AS ok FROM $(opt.schema).licenses;") |>
#         rowtable |>
#         (data -> data[1].ok)
# end
# @testset "Repos" begin
#     data = execute(opt.conn,
#                    "SELECT spdx, created_query FROM $(opt.schema).spdx_queries ORDER BY spdx ASC, created_query ASC;") |>
#         rowtable
#     foreach(row -> repos(opt, row...), data)
#     @test execute(opt.conn,
#                   "SELECT COUNT(*) = 0 AS ok FROM $(opt.schema).spdx_queries WHERE status != 'Done';") |>
#         rowtable |>
#         (data -> data[1].ok)
# end
# @testset "Commits" begin
#     data = execute(opt.conn, "SELECT slug FROM $(opt.schema).repos ORDER BY slug ASC LIMIT 1;") |>
#         rowtable
#     foreach(row -> commits(opt, row...), data)
#     @test execute(opt.conn,
#                   "SELECT COUNT(*) = 1 AS ok FROM $(opt.schema).repos WHERE status = 'Done';") |>
#           rowtable |>
#           (data -> data[1].ok)
#     execute(opt.conn, "UPDATE $(opt.schema).repos SET status = 'Initiated'";)
#     execute(opt.conn,
#             """DELETE FROM $(opt.schema).commits
#                WHERE committed_date <=
#                  (SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY committed_date ASC) AS median
#                FROM $(opt.schema).commits);
#             """)
#     foreach(row -> commits(opt, row...), data)
#     @test execute(opt.conn,
#                   "SELECT COUNT(*) = 1 AS ok FROM $(opt.schema).repos WHERE status = 'Done';",
#                   not_null = true) |>
#         rowtable |>
#         (data -> data[1].ok)
# end
# @testset "Documentation" begin
#     using Documenter, GHOSS
#     using GHOSS: BaseUtils, Licenses, Search, Repos, Commits

#     DocMeta.setdocmeta!(GHOSS,
#                        :DocTestSetup,
#                        :(using GHOSS, DataFrames, Printf;
#                         opt = Opt("Nosferican",
#                                   ENV["GITHUB_TOKEN"],
#                                   host = ENV["POSTGIS_HOST"],
#                                   port = parse(Int, ENV["POSTGIS_PORT"]));),
#                        recursive = true)
#     makedocs(sitename = "GHOSS",
#              modules = [GHOSS],
#              pages = [
#                  "Home" => "index.md",
#                  "Manual" => "manual.md",
#                  "API" => "api.md"
#              ],
#              source = joinpath("..", "docs", "src"),
#              build = joinpath("..", "docs", "build"),
#              )
#     @test true
# end
