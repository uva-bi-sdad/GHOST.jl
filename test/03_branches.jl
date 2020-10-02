run(`ijob -A biocomplexity -p bii -t 0-04:00:00 -c 30 --mem=256GB`)
julia --proj

filter!(isequal(joinpath(homedir(), ".julia")), DEPOT_PATH)

using GHOSS

conn = Connection("""
                  host = $(get(ENV, "PGHOST", ""))
                  dbname = sdad
                  user = $(get(ENV, "DB_USR", ""))
                  password = $(get(ENV, "DB_PWD", ""))
                  """);
pats = execute(conn, "SELECT * FROM gh.pat ORDER BY login LIMIT 3;", not_null = true) |>
    DataFrame |>
    (data -> [ GitHubPersonalAccessToken(row.login, row.pat) for row in eachrow(data) ])
pat = pats[end]

setup_parallel(pats)
schema = "gh_2007_2019"
querydata = execute(conn,
                    """
                    SELECT spdx, created, count
                    FROM gh_2007_2019.queries
                    ORDER BY count DESC
                    ;
                    """,
                    not_null = true) |>
    DataFrame
querydata.created = Interval.(ZonedDateTime.(getproperty.(querydata.created, :first), utc_tz), ZonedDateTime.(getproperty.(querydata.created, :last), utc_tz))

branches(conn, querydata[1:12,[:spdx,:created]])

names(querydata)
unique(querydata[!,[:spdx,:created]])
querydata₀ = querydata[1:4,:]
querydata₀[!, :id] = repeat(1:2, inner = 2)
querydata₀ = groupby(querydata₀, :id)
data₀ = querydata[1:2,:]
data₁ = querydata[3:4,:]

for subdf in querydata₀
    result, tracker = branches(pat, subdf)
end
result₀, tracker₀ = branches(pat, data₀)
result₁, tracker₁ = branches(pat, data₁)

@everywhere function magic(slug)
    branches(pat, slug)
end
for w in eachindex(ready)
    slug = popfirst!(slugs)
    ready[w] = remotecall(magic, w + 1, slug)
end
while !isempty(slugs)
    w = findfirst(isready, ready)
    println(w)
    if isnothing(w)
        sleep(30)
    else
        slug = popfirst!(slugs)
        ready[w] = remotecall(magic, w + 1, slug)
    end
end
while any(!isready, ready)
    sleep(60)
end


data = querydata[1:2,:]
time_start = now()
result = branches(pat, data)
time_end = now()
println(Dates.canonicalize(Dates.CompoundPeriod(time_end - time_start)))
