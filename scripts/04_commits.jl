using GHOST
using GHOST: @unpack
setup()
setup_parallel()
@unpack conn, schema = GHOST.PARALLELENABLER
data = execute(conn,
               String(read(joinpath(pkgdir(GHOST), "src", "assets", "sql", "branches_min_max.sql"))) |>
                   (obj -> replace(obj, "schema" => schema)) |>
                   (obj -> replace(obj, "min_lim" => 0)) |>
                   (obj -> replace(obj, "max_lim" => 100)),
               not_null = true) |>
    (obj -> getproperty.(obj, :branch))
time_start = now()

idx = (1:8:500)[6]
query_commits(view(data, idx:min(idx + 7, lastindex(data))), 100)

println(time_start)
# @sync @distributed for idx in 1:8:500
for idx in 1:8:500
    query_commits(view(data, idx:min(idx + 7, lastindex(data))), 100)
    sleep(0.25)
end
time_end = now()
canonicalize(CompoundPeriod(time_end - time_start))
