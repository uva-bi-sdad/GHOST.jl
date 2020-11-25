using GHOSS
using GHOSS: @unpack
setup()
setup_parallel()
@unpack conn, schema = GHOSS.PARALLELENABLER
data = execute(conn,
               String(read(joinpath(dirname(pathof(GHOSS)), "assets", "sql", "branches_min_max.sql"))) |>
                   (obj -> replace(obj, "schema" => schema)) |>
                   (obj -> replace(obj, "min_lim" => 0)) |>
                   (obj -> replace(obj, "max_lim" => 100)),
               not_null = true) |>
    (obj -> getproperty.(obj, :branch))
time_start = now()
println(time_start)
@sync @distributed for idx in 1:8:lastindex(data)
    query_commits_simple(view(data, idx:min(idx + 7, lastindex(data))), 100)
    sleep(1)
end
time_end = now()
canonicalize(CompoundPeriod(time_end - time_start))
