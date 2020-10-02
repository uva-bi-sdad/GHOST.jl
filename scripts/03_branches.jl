using GHOSS
using GHOSS: @unpack, groupby
using Distributed
setup()
setup_parallel()
@unpack conn, schema = GHOSS.PARALLELENABLER

data = execute(conn, String(read(joinpath("src", "assets", "sql", "queries_batches.sql"))), not_null = true) |>
    DataFrame |>
    (df -> groupby(df, [:queries, :query_group]));
data = [ data[k] for k in keys(data) ];

time_start = now()
find_repos(data[begin])
time_end = now()
canonicalize(CompoundPeriod(time_end - time_start))
