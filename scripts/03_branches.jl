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
@sync @distributed for batch in data
    find_repos(batch)    
end
time_start = now()
canonicalize(CompoundPeriod(time_end - time_start))
