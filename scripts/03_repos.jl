using GHOST
using GHOST: @unpack, groupby
using Distributed
setup()
setup_parallel()
@unpack conn, schema = GHOST.PARALLELENABLER

data = execute(conn, String(read(joinpath(dirname(pathof(GHOST)), "assets", "sql", "queries_batches.sql"))), not_null = true) |>
    DataFrame |>
    (df -> groupby(df, [:queries, :query_group]));
data = [ data[k] for k in keys(data) ];



time_start = now()
# @sync @distributed for batch in data
#     find_repos(batch)
# end
find_repos(data[1])
time_end = now()
canonicalize(CompoundPeriod(time_end - time_start))
