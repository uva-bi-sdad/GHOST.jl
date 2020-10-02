using GHOSS

conn = Connection("dbname = sdad")
spdx = "mit"
# created = floor(GH_FIRST_REPO_TS, Day):Day(1):DateTime(floor(now(utc_tz), Year), UTC)
# created = Interval.(created[begin:end - 1], created[nextind(created, firstindex(created)):end], true, false)

spdxs = execute(conn, "SELECT spdx FROM $schema.licenses ORDER BY spdx;", not_null = true) |>
    (obj -> getproperty.(obj, :spdx))

function find_repo_count_for_intervals(spdx, created)
    repositoryCount = zeros(UInt32, length(created))
    indices = range(firstindex(created), lastindex(created), step = 286)
    for idx₀ in indices
        vals = idx₀:min(idx₀ + step(indices) - 1, lastindex(created))
        subsquery = join([ string("_$idx:search(query:\"is:public fork:false mirror:false archived:false license:$spdx created:",
                                  format(created[idx].first, "yyyy-mm-ddTHH:MM:SS+00"),
                                  "..",
                                  format(created[idx].last, "yyyy-mm-ddTHH:MM:SS+00"),
                                  "\",type:REPOSITORY){...A}") for idx in vals
                         ]);
        query = "fragment A on SearchResultItemConnection{repositoryCount} query Search{$subsquery}" |>
            (obj -> replace(obj, r"\s+" => " ")) |>
            strip |>
            string;
        try
            sleep(0.75)
            result = graphql(;query = query)
            json = JSON3.read(result.Data)
            repositoryCount[vals] .= getproperty.(values(json.data), :repositoryCount)
        catch err
            println(vals)
            println(result)
            println(err)
        end
    end
    data = DataFrame(created = created, count = repositoryCount)
    pruned = prune(data)
    cleaned_prune = reduce(vcat, cleanintervals(row) for row in eachrow(pruned))
end
function fill_missing_intervals(spdx, data)
    new_data = find_repo_count_for_intervals(spdx, data.created[ismissing.(data.count)])
    new_data = join(data, new_data, on = :created, makeunique = true)
    new_data[!,:count] .= coalesce.(new_data.count_1, new_data.count)
    pruned = prune(new_data[!,[:created, :count]])
    cleaned_prune = reduce(vcat, cleanintervals(row) for row in eachrow(pruned))
end
function find_queries(spdx)
    created = vcat(DateTime("2009-01-01") - GH_FIRST_REPO_TS,
                   fill(Month(6), 2),
                   fill(Month(4), 3),
                   fill(Month(2), 6),
                   fill(Month(1), 12),
                   fill(Day(5), 73))
    created = vcat(GH_FIRST_REPO_TS, GH_FIRST_REPO_TS .+ cumsum(created))
    created = vcat(created, created[end]:Day(1):DateTime(year(floor(now(utc_tz), Year))))
    created = Interval.(created[begin:end - 1], created[nextind(created, firstindex(created)):end], true, false)
    data = find_repo_count_for_intervals(spdx, created)
    while any(ismissing, data.count)
        data = fill_missing_intervals(spdx, data)
    end
    data[!,:spdx] .= spdx
    data[!,[:spdx, :created, :count]]
end

x = find_queries(spdxs[1])

queries_intervals = Vector{DataFrame}(undef, length(spdxs))
time_start = now()
for idx in eachindex(spdxs)
    queries_intervals[idx] = find_queries(spdxs[idx])
end
time_end = now()
Dates.canonicalize(Dates.CompoundPeriod(time_end - time_start))

round(time_end - time_start, Minute)
# 4967
queries = reduce(vcat, queries_intervals)
queries[!,:created] .= replace.(string.(queries[!,:created]), " .." => ",")
execute(conn, "BEGIN;")
load!(queries,
      conn,
      """
      INSERT INTO $schema.queries (spdx, created, count) VALUES(\$1,\$2,\$3)
      ON CONFLICT ON CONSTRAINT nonoverlappingqueries DO NOTHING;
      """)
execute(conn, "COMMIT;")


[ find_queries(spdx) ]

time_start = now()
queries_mit = find_queries(spdx)
time_end = now()
round(time_end - time_start, Minute)

time_start = now()
first_stage = find_repo_count_for_intervals(spdx, created)
time_end = now()
round(time_end - time_start, Minute)
time_start = now()
second_stage = find_repo_count_for_intervals(spdx, first_stage.created[ismissing.(first_stage.count)])
time_end = now()
round(time_end - time_start, Minute)
new_data = join(first_stage, second_stage, on = :created, makeunique = true)
new_data[!,:count] .= coalesce.(new_data.count_1, new_data.count)
new_data = new_data[!,[:created, :count]]



findall(iszero, repositoryCount)
indices = range(firstindex(created), lastindex(created), step = 296)

data = DataFrame(created = created, count = repositoryCount)
pruned = prune(data)
cleaned_prune = reduce(vcat, cleanintervals(row) for row in eachrow(pruned))
to_fill = cleaned_prune[ismissing.(cleaned_prune.count),:]



string(DateTime("2000-01-01"), "+00")
subsquery = join([ string("_$idx:search(query:\"is:public fork:false mirror:false archived:false license:$spdx created:",
                          format(created[idx].first, "yyyy-mm-ddTHH:MM:SS+00"),
                          "..",
                          format(created[idx].last, "yyyy-mm-ddTHH:MM:SS+00"),
                          "\",type:REPOSITORY){...A}") for idx in eachindex(created[1:500])]);
query = "fragment A on SearchResultItemConnection{repositoryCount} query Search{$subsquery}" |>
    (obj -> replace(obj, r"\s+" => " ")) |>
    strip |>
    string;
result = graphql()
json = JSON3.read(result.Data)
data = json.data
data[:_1]
output = DataFrame(created = created[1:500], count = getproperty.(values(data), :repositoryCount))
great = prune(output)

function factorize(number, primes)
    factor = Int64[]
    for p in primes
        while number % p == 0
            push!(factor, p)
            number = number ÷ p
        end
        if number == 1
            break
        end
    end
    if number > 1
        @warn "factorization failed, not enough primes passed; printing only factors found in primes vector"
    end
    return factor
end

4448 ÷ 14
