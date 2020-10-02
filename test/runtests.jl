run(`ijob -A biocomplexity -p bii -t 0-04:00:00 -c 30 --mem=256GB`)
julia --proj

filter!(isequal(joinpath(homedir(), ".julia")), DEPOT_PATH)
# using Revise
# using Distributed
# addprocs(parse(Int, ENV["SLURM_CPUS_PER_TASK"]) - 1, exeflags = `--proj`)
# @everywhere using Revise
using Test
using LibPQ: Connection, execute, rowtable
conn = Connection("dbname = sdad");
using GHOSS
using GHOSS: floor, now, Date, Year, year, format, utc_tz
const LASTFULLCALENDARYEAR = year(floor(now(utc_tz), Year)) - 1
schema = "gh_2007_$LASTFULLCALENDARYEAR"

VERSION
run(`ijob -A biocomplexity -p bii -t 0-02:00:00 -c 31 --mem=350GB`)
ml julia/1.3.1
julia --proj
# using Distributed
# using LibPQ: Connection, execute, rowtable
using GHOSS
using Distributed
conn = Connection("dbname = sdad");
pats = execute(conn, "SELECT login, pat FROM gh.pat ORDER BY login;", not_null = true) |>
    DataFrame |>
    (data -> [ GitHubPersonalAccessToken(row.login, row.pat) for row in eachrow(data) ])
setup_parallel(pats)
spdxs = execute(conn, "SELECT spdx FROM gh_2007_2019.licenses ORDER BY spdx;", not_null = true) |>
    (obj -> getproperty.(obj, :spdx))



x = GHOSS.find_queries(spdxs[1])

Distributed.remotecall_eval(Main, 2, :(conn = Ref($conn);))

addprocs(1, exeflags = `--proj`)

@spawnat 2 using LibPQ: Connection

@everywhere using GHOSS
@everywhere conn = Connection("dbname = sdad");
for proc ∈ workers()
    # login, token = login_token[proc - 1]
    expr = :(conn = Connection("dbname = sdad");
             )
    Distributed.remotecall_eval(Main, proc, expr)
end
using Distributed
addprocs(1, exeflags = `--proj`)
@everywhere using LibPQ: Connection
@everywhere conn = Connection("dbname = sdad");
fetch(@spawnat(2, conn))

fetch(@spawnat(2, ENV["PGHOST"]))

GHOSS.PARALLELENABLER

for proc ∈ workers()
    login, token = login_token[proc - 1]
    expr = :(opt = Opt($login, $token,
                       db_usr = $db_usr, db_pwd = $db_pwd,
                       host = "postgis1", dbname = "sdad",
                       schema = "gh", role = "ncses_oss");
             )
    Distributed.remotecall_eval(Main, proc, expr)
end

for proc ∈ workers()
    login, token = login_token[proc - 1]
    expr = :(opt = Opt($login, $token,
                       db_usr = $db_usr, db_pwd = $db_pwd,
                       host = "postgis1", dbname = "sdad",
                       schema = "gh", role = "ncses_oss");
             )
    Distributed.remotecall_eval(Main, proc, expr)
end



pat = pats[1]



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

schema = 

@testset "Setup" begin
    # execute(conn, "DROP SCHEMA IF EXISTS $schema CASCADE;")
    execute(conn, "DROP TABLE $schema.queries CASCADE;")
    setup(conn)
    @test execute(conn,
                  "SELECT COUNT(*) > 0 AS ok FROM information_schema.schemata WHERE schema_name = '$schema';") |>
        rowtable |>
        (data -> data[1].ok)
end
@testset "Licenses" begin
    licenses(conn, pat)
    @test execute(conn, "SELECT COUNT(*) > 30 AS ok FROM gh_2007_2019.licenses;", not_null = true) |>
        DataFrame |>
        (data -> data.ok[1])
end
@testset "Search" begin
    # Non-overlaping consecutive intervals over the desired time range.
    @test execute(conn,
                  String(read(joinpath(@__DIR__, "test", "assets", "graphql", "queries.sql")))) |>
        DataFrame |>
        (data -> data.valid[1])
end
# @testset "Repos" begin
#     data = execute(conn,
#                    "SELECT spdx, created_query FROM $schema.spdx_queries ORDER BY spdx ASC, created_query ASC;") |>
#         rowtable
#     foreach(row -> repos(opt, row...), data)
#     @test execute(conn,
#                   "SELECT COUNT(*) = 0 AS ok FROM $schema.spdx_queries WHERE status != 'Done';") |>
#         rowtable |>
#         (data -> data[1].ok)
# end
# @testset "Commits" begin
#     data = execute(conn, "SELECT slug FROM $schema.repos ORDER BY slug ASC LIMIT 1;") |>
#         rowtable
#     foreach(row -> commits(opt, row...), data)
#     @test execute(conn,
#                   "SELECT COUNT(*) = 1 AS ok FROM $schema.repos WHERE status = 'Done';") |>
#           rowtable |>
#           (data -> data[1].ok)
#     execute(conn, "UPDATE $schema.repos SET status = 'Initiated'";)
#     execute(conn,
#             """DELETE FROM $schema.commits
#                WHERE committed_date <=
#                  (SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY committed_date ASC) AS median
#                FROM $schema.commits);
#             """)
#     foreach(row -> commits(opt, row...), data)
#     @test execute(conn,
#                   "SELECT COUNT(*) = 1 AS ok FROM $schema.repos WHERE status = 'Done';",
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
