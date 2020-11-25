using GHOSS
using GHOSS: @unpack
setup()
setup_parallel()
@unpack conn, schema, pat = GHOSS.PARALLELENABLER
data = execute(conn,
               "SELECT branch FROM $(schema).repos WHERE status = 'Init' ORDER BY commits;",
               not_null = true) |>
    (obj -> getproperty.(obj, :branch))
time_start = now()
println(time_start)
@sync @distributed for branch in data
    query_commits(branch)
    sleep(1)
end
time_end = now()
canonicalize(CompoundPeriod(time_end - time_start))
